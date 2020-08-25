FROM openanalytics/r-base

LABEL maintainer "FINEPRINT <jakob.gutschlhofer@wu.ac.at>"

# Install a few dependencies for packages
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  libxml2-dev \
  libcairo2-dev \
  libsqlite3-dev \
  libpq-dev \
  libssl-dev \
  libcurl4-openssl-dev \
  libssh2-1-dev \
  unixodbc-dev \
  libgdal-dev \
  libgeos-dev \
  liblwgeom-dev \
  libssl-dev \
  libudunits2-dev \
  && install2.r --error \
    devtools \
    tidyverse \
    DBI \
    RPostgreSQL \
    pool \
    shiny \
    shinyjs \
    plotly \
    sf \
    httr \
    lwgeom \
    shinyWidgets \
    mapedit

# Add shiny user
RUN groupadd  shiny \
&& useradd --gid shiny --shell /bin/bash --create-home shiny

# copy the app to the image
RUN mkdir /home/shiny/mva
COPY /app /home/shiny/mva/
COPY /app/.Renviron /home/shiny/

# Make all app files readable
RUN chmod -R +r /home/shiny/mva/

# Some shiny app settings
COPY Rprofile.site /usr/lib/R/etc/

# Make shiny the owner of /home/shiny/ in order to be able to access .Renviron
RUN chown -R shiny.shiny /home/shiny/

# Now run everything as user shiny
USER shiny

EXPOSE 3838

CMD ["R", "-e", "setwd('/home/shiny/mva')"]
CMD ["R", "-e", "shiny::runApp('/home/shiny/mva')"]
