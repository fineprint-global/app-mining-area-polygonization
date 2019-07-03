# Get shiny server with tidyverse installed already
FROM rocker/shiny-verse:3.5.3

# Install a few dependencies for packages
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
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
    shinyWidgets

# install custom version of mapedit
RUN R -e "devtools::install_github('Gutschlhofer/mapedit', force = TRUE)"

# Copy configuration files into the Docker image
COPY shiny-server.conf  /etc/shiny-server/shiny-server.conf

# Make the ShinyApp available at port 80
EXPOSE 80

# Copy further configuration files into the Docker image
COPY shiny-server.sh /usr/bin/shiny-server.sh

# RUN ["chmod", "+x", "/usr/bin/shiny-server.sh"]

CMD ["/usr/bin/shiny-server.sh"]
