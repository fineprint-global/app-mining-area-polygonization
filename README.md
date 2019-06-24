# Mine vectorization application
A web application to poligonize mine-areas in a given set of locations.

The purpose of this project is to ... using R and PostgreSQL. There are two components, an R Shiny web application and a PostgreSQL Database (more specifically a postgis one). The network of those two components can be created with one single `docker-compose` command.

**Disclaimer:** This app is work in progress and has not been completed. This means that while you can still use certain parts, the app as a whole will not work.

## Usage
1. [Dependencies](#dependencies)
2. [Get the app](#get-the-app)
3. [Setup](#setup)
4. [How to run](#how-to-run)
5. [How to restart/stop](#how-to-restart-or-stop-the-app)

### Dependencies
In order to run the app, you need the following tools installed:

#### Docker and Docker Compose
To install Docker and Docker Compose (comes already installed with Docker Desktop) for you system follow the links below:

- Mac: [Install Docker Desktop for Mac](https://docs.docker.com/docker-for-mac/install/) to get Docker and Docker Compose installed
- Windows: [Install Docker Desktop for Windows](https://docs.docker.com/docker-for-windows/install/) to get Docker and Docker Compose installed
- Ubuntu:
    - [Docker](https://docs.docker.com/install/linux/docker-ce/ubuntu/)
    - [Docker Compose](https://docs.docker.com/compose/install/)
- Other systems:
    - [Docker](https://docs.docker.com/install/)
    - [Docker Compose](https://docs.docker.com/compose/install/)

#### (git)
You only need git installed if you want to contribute to the repository or clone it without having to download it manually.

#### (R and RStudio)
You only need R (version 3.5 or higher) and RStudio installed in case you would like to make your own changes to the app and try them out before you create the docker containers.

If you are on a Linux machine, you need to install the following packages via `apt` (or any other package manager) as they are required by the R packages needed:
`sudo apt install libpq-dev libssl-dev libxml2-dev libcurl4-openssl-dev`

The command to install the R packages can be found on the respective file you want to edit.

### Get the app
To get the app, you can either

- download the source using the "Clone or download"-button above
- use `git clone https://github.com/fineprint-global/mine-poligonization-app.git`

### Setup
There are a few settings that you have to make before you can run the app.

#### `.env` file in the root directory
You have to set the following variables, here is an example `.env` file:

```
POSTGRES_PASSWORD=secret
POSTGRES_PORT=5454
SHINY_PORT=80
```

#### `.Renviron` file in the `/app` directory
In the `.Renviron` file, make sure the `POSTGRES_PORT` in the `.env` file and the `db_port` match. Here is an example file that needs to be created inside the `/app` directory.

```
db_host=mva_db
db_port=5454
db_name=mine_area
db_user=app
db_password=secret
```

### How to run
There are two ways to run this app.

1. You can run it as is, with a pre-loaded database.
2. You can use your own data, which requires you to adapt the scripts in the [data-to-db](https://github.com/fineprint-global/mine-poligonization-app/tree/master/db/data-to-db) directory.
3. You can leave the database as is and change the visualizations.

#### 1. Run as is

1. Make sure all necessary dependencies are installed.
2. Make sure Docker (Desktop) is up and running.
3. Make sure you completed the steps in [setup](#setup)
4. Navigate to the root directory (`mine-poligonization-app`) with a shell of your choice and run the following command:
`docker-compose up -d`

Now both, the `mva_app` (RShiny app) and the `mva_db` (postgis database) should be running on ports specified in the `docker-compose.yml` on your localhost (e.g. ports `80` and `5454` respectively). To verify that both containers are running and the ports are correct, you can run `docker-compose ps` (in the root directory) or `docker ps` (anywhere).

You should now be able to see the app running at [localhost:80](localhost:80) or – if not `80` – at the port you specified in `SHINY_PORT`.

If there are any problems, check out the [troubleshooting](#troubleshooting) section.

#### 2. Use your own data
More detailed instructions on this will come soon, but you will have to adjust the `main.R` located in the [data-to-db](https://github.com/fineprint-global/mine-poligonization-app/tree/master/db/data-to-db) directory to load your own input-output table and adjust it to the proper database format.

##### 2.1 Database format
In order for your input-output table to be used with the Shiny app, you first need to adjust it to the database format used for this application.

The database format can be found in the [db](https://github.com/fineprint-global/mine-poligonization-app/tree/master/db) folder in both `.dbm` format (to be viewed and edited via [pgmodeler](https://pgmodeler.io/)) and `.png` formats.

Check out the `main.R` file to see how our data was taken from `.rds` files and modified to fit the database format.

#### 3. Change the visualizations
The folders to take care of are the [app](https://github.com/fineprint-global/mine-poligonization-app/tree/master/app/) folder and the [docker-rshiny](https://github.com/fineprint-global/mine-poligonization-app/tree/master/docker-rshiny/) folder. The `app` folder will be used to change the visualizations whereas the `docker-rshiny` folder needs to be kept in mind for any new packages you might require.

##### 3.1 `app` folder
Before you dive into this, if you are new to RShiny, you may want to check out this [tutorial](https://shiny.rstudio.com/tutorial/).

In our example, the `app` folder is divided into 4 main files:

- `app.R`: you should not need to add anything there, this just brings all three other files together
- `global.R`: this will be executed once for every worker process, not for every user, so this is where you specify database connections and perform other setup-related tasks
- `ui.R`: you specify the UI here. `output` elements (e.g. `uiOutput`) are defined here and respective `render` functions (e.g. `renderText`) for those are performed in the `server.R`. If you want to add new visualizations or other elements, define them here.
- `server.R`: any new visualizations defined in the `ui.R` should be implemented in the `server.R`, this is where you collect your data, bring it into the correct format and then define the output-layout (e.g. for `plotly`).

##### 3.2 `docker-rshiny` folder for packages
You need to edit the [Dockerfile](https://github.com/fineprint-global/mine-poligonization-app/tree/master/docker-rshiny/Dockerfile) if you add any new packages that are not included yet.

As an example, in this part of the Dockerfile …
```Dockerfile
...
# Install a few dependencies for packages
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  && install2.r --error \
    plotly \
    RPostgreSQL \
    pool
...
```
… you could edit it to include `leaflet` to add map functionalities:
```Dockerfile
    ...
    pool \
    leaflet
...
```

### How to restart or stop the app
- To restart the containers, run `docker-compose restart`
- To stop the containers, move to the `mine-poligonization-app` directory and run `docker-compose stop`
- To stop containers and to remove containers, networks, volumes, and images created by `docker-compose up`, run `docker-compose down`

## Troubleshooting
*This section is still to come.*

- make sure you have all dependencies (packages etc.) installed, you may want to check out the RShiny Dockerfile for any packages necessary for the app to run

### Windows-Issues with RShiny Docker

In case there are issues with building and running the RShiny Docker from the directory (especially in Windows file permissions tend to get messed up, and then the container is constantly restarting, sometimes with the error: `standard_init_linux.go:207: exec user process caused "no such file or directory"`), you can alternatively use the docker image from Docker Hub. For this, you need to replace the build context with the Docker Hub image like below:
```YAML
    # build:
    #   context: ./docker-rshiny
    image: fineprint/mva
```

## Acknowledgement
This project gratefully acknowledges financial support from the ERC as part of the [FINEPRINT](https://www.fineprint.global/) project.
