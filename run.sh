#!/bin/bash

set -eo pipefail

# Create a profile for 'notebook'. Add code for setting password for
# the notebook from an environment variable.

jupyter notebook --generate-config

cat >> ${HOME}/.jupyter/jupyter_notebook_config.py << !
import os
password = os.environ.get('JUPYTER_NOTEBOOK_PASSWORD')
if password:
    import notebook.auth
    c.NotebookApp.password = notebook.auth.passwd(password)
    del password
    del os.environ['JUPYTER_NOTEBOOK_PASSWORD']
!

# Create a profile for 'ipyparallel'. Create definitions files for
# communicating between the client, controller and engines using known
# ports and security keys. Also enable communication outside of the host
# so can distribute cluster across nodes.

ipython profile create --parallel

IPYPARALLEL_CONTROLLER_NAME=${IPYPARALLEL_CONTROLLER_NAME:-localhost}

TOKEN_FILE=/run/secrets/kubernetes.io/serviceaccount/token

if [ -f ${TOKEN_FILE} ]; then
    TOKEN=`cat /run/secrets/kubernetes.io/serviceaccount/token`
    IPYPARALLEL_SECRET_KEY=`echo -n $TOKEN | \
        openssl dgst -sha256 -hmac "${IPYPARALLEL_CONTROLLER_NAME}" | \
        sed -e 's/^.* //'`
else
    IPYPARALLEL_SECRET_KEY="abcd1234-abcd-1234-abcd-1234abcd1234"
fi

cat >> ${HOME}/.ipython/profile_default/ipcontroller_config.py << !
c.IPControllerApp.reuse_files = True
c.RegistrationFactory.ip = u'*'
c.HubFactory.engine_ip = u'*'
c.HubFactory.client_ip = u'*'
c.HubFactory.monitor_ip = u'*'
!

cat >> ${HOME}/.ipython/profile_default/ipengine_config.py << !
c.RegistrationFactory.ip = u'*'
!

cat > ${HOME}/.ipython/profile_default/security/ipcontroller-client.json << !
{
  "control": 10000,
  "interface": "tcp://${IPYPARALLEL_CONTROLLER_NAME}",
  "iopub": 10001,
  "key": "${IPYPARALLEL_SECRET_KEY}",
  "location": "${IPYPARALLEL_CONTROLLER_NAME}",
  "mux": 10002,
  "notification": 10003,
  "pack": "json",
  "registration": 10004,
  "signature_scheme": "hmac-sha256",
  "ssh": "",
  "task": 10005,
  "task_scheme": "leastload",
  "unpack": "json"
}
!

cat > ${HOME}/.ipython/profile_default/security/ipcontroller-engine.json << !
{
  "control": 10006,
  "hb_ping": 10007,
  "hb_pong": 10008,
  "interface": "tcp://${IPYPARALLEL_CONTROLLER_NAME}",
  "iopub": 10009,
  "key": "${IPYPARALLEL_SECRET_KEY}",
  "location": "${IPYPARALLEL_CONTROLLER_NAME}",
  "mux": 10010,
  "pack": "json",
  "registration": 10004,
  "signature_scheme": "hmac-sha256",
  "ssh": "",
  "task": 10011,
  "unpack": "json"
}
!

unset IPYPARALLEL_SECRET_KEY

# Start up as 'ipyparallel' controller process if enabled.

if [ x"${IPYPARALLEL_SERVICE_TYPE}" = x"controller" ]; then
    unset JUPYTER_NOTEBOOK_PASSWORD
    exec ipcontroller
fi

# Start up as 'ipyparallel' engine process if enabled.

if [ x"${IPYPARALLEL_SERVICE_TYPE}" = x"engine" ]; then
    unset JUPYTER_NOTEBOOK_PASSWORD
    exec ipengine
fi

# Enable notebook server extensions.

if [ x"${JUPYTER_SERVER_EXTENSIONS}" != x"" ]; then
    for extension in $(echo ${JUPYTER_SERVER_EXTENSIONS} | tr "," " "); do
        jupyter serverextension enable --py ${extension} --user
    done
fi

# Install assets and enable notebook extensions.

if [ x"${JUPYTER_NOTEBOOK_EXTENSIONS}" != x"" ]; then
    for extension in $(echo ${JUPYTER_NOTEBOOK_EXTENSIONS} | tr "," " "); do
        jupyter nbextension install --py ${extension} --user
        jupyter nbextension enable --py ${extension} --user
    done
fi

# Start the Jupyter notebook instance.

JUPYTER_NOTEBOOK_DIR=${JUPYTER_NOTEBOOK_DIR:-${WARPDRIVE_SRC_ROOT}}

exec jupyter notebook --no-browser --ip=* --port=8080 \
  --notebook-dir=${JUPYTER_NOTEBOOK_DIR}
