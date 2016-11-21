FROM grahamdumpleton/warp0-debian8-python35

# We need to extend the image so we have to be root.

USER root

# Install any additional system packages. These are required by Jupyter
# notebook or various modules for data analysis and visualisation.

RUN apt-get update && apt-get install -y libfreetype6 libfreetype6-dev \
    libpng++ libpng++-dev liblapack-dev libatlas-dev gfortran \
    libav-tools libgeos-dev && \
    apt-get clean && \
    rm -r /var/lib/apt/lists/*

# Copy in S2I scripts and override S2I labels to flag this as now being
# builder for Jupyter notebooks.

COPY s2i ${WARPDRIVE_APP_ROOT}/.s2i
COPY run.sh ${WARPDRIVE_APP_ROOT}/run.sh

LABEL io.k8s.description="S2I builder for Jupyter Notebooks (Python 3.5)." \
      io.k8s.display-name="Jupyter Notebook (Python 3.5)" \
      io.openshift.tags="builder,python,python35,jupyter"

# Switch back to non 'root' user. Must use the uid and not the user name
# else will be rejected by 's2i' under OpenShift as can't know whether
# is pretending to be a non 'root' user.

USER 1001

# Install module for Jupyter notebook and ipyparallel.

RUN pip install --no-cache-dir jupyter ipython[notebook] ipyparallel

# Expose ports needed when running a parallel compute cluster using the
# ipyparallel module.

EXPOSE 10000-10011

# Override 'CMD' so we can wrap the startup of Jupyter notebook or switch
# it out and instead run 'ipengine' or 'ipcontroller' when running a
# parallel compute cluster.

CMD [ "/opt/app-root/s2i/bin/run" ]
