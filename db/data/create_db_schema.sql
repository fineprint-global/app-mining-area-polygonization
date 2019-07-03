-- Database generated with pgModeler (PostgreSQL Database Modeler).
-- pgModeler  version: 0.9.1
-- PostgreSQL version: 10.0
-- Project Site: pgmodeler.io
-- Model Author: ---

-- object: app | type: ROLE --
-- DROP ROLE IF EXISTS app;

-- Prepended SQL commands --
DROP ROLE IF EXISTS app;
-- ddl-end --

CREATE ROLE app WITH 
	LOGIN
	ENCRYPTED PASSWORD 'YOURPASSWORD';
-- ddl-end --


-- Database creation must be done outside a multicommand file.
-- These commands were put in this file only as a convenience.
-- -- object: vector_mine | type: DATABASE --
-- -- DROP DATABASE IF EXISTS vector_mine;
-- CREATE DATABASE vector_mine
-- 	OWNER = postgres;
-- -- ddl-end --
-- 

-- object: postgis | type: EXTENSION --
-- DROP EXTENSION IF EXISTS postgis CASCADE;
CREATE EXTENSION postgis
;
-- ddl-end --

-- object: public.mine_polygon | type: TABLE --
-- DROP TABLE IF EXISTS public.mine_polygon CASCADE;
CREATE TABLE public.mine_polygon(
	id bigserial NOT NULL,
	geometry geometry(MULTIPOLYGON),
	created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
	status varchar(10) NOT NULL,
	note text,
	version smallint NOT NULL,
	revision smallint NOT NULL,
	seconds_spent float NOT NULL,
	id_mine_cluster bigint NOT NULL,
	id_app_user char(7) NOT NULL,
	CONSTRAINT mine_polygon_pk PRIMARY KEY (id)

);
-- ddl-end --
ALTER TABLE public.mine_polygon OWNER TO postgres;
-- ddl-end --

-- object: idx_mine_polygon | type: INDEX --
-- DROP INDEX IF EXISTS public.idx_mine_polygon CASCADE;
CREATE INDEX idx_mine_polygon ON public.mine_polygon
	USING btree
	(
	  id
	);
-- ddl-end --

-- object: public.mine_point | type: TABLE --
-- DROP TABLE IF EXISTS public.mine_point CASCADE;
CREATE TABLE public.mine_point(
	id bigserial NOT NULL,
	geometry geometry(POINT) NOT NULL,
	fp_id serial NOT NULL,
	mine_name varchar(50),
	country varchar(100),
	list_of_commodities varchar(250),
	development_stage varchar(50),
	operating_status varchar(50),
	coordinate_accuracy varchar(20),
	known_as text,
	mine_type varchar(50),
	id_mine_cluster bigint NOT NULL,
	CONSTRAINT mine_point_pk PRIMARY KEY (id)

);
-- ddl-end --
ALTER TABLE public.mine_point OWNER TO postgres;
-- ddl-end --

-- object: idx_geom_polygon | type: INDEX --
-- DROP INDEX IF EXISTS public.idx_geom_polygon CASCADE;
CREATE INDEX idx_geom_polygon ON public.mine_polygon
	USING gist
	(
	  geometry
	);
-- ddl-end --

-- object: idx_mine_point | type: INDEX --
-- DROP INDEX IF EXISTS public.idx_mine_point CASCADE;
CREATE INDEX idx_mine_point ON public.mine_point
	USING btree
	(
	  id
	);
-- ddl-end --

-- object: idx_geom_point | type: INDEX --
-- DROP INDEX IF EXISTS public.idx_geom_point CASCADE;
CREATE INDEX idx_geom_point ON public.mine_point
	USING gist
	(
	  geometry
	);
-- ddl-end --

-- object: public.mine_cluster | type: TABLE --
-- DROP TABLE IF EXISTS public.mine_cluster CASCADE;
CREATE TABLE public.mine_cluster(
	id bigserial NOT NULL,
	id_app_user char(7) NOT NULL,
	CONSTRAINT mine_cluster_pk PRIMARY KEY (id)

);
-- ddl-end --
ALTER TABLE public.mine_cluster OWNER TO postgres;
-- ddl-end --

-- object: idx_mine_cluster | type: INDEX --
-- DROP INDEX IF EXISTS public.idx_mine_cluster CASCADE;
CREATE INDEX idx_mine_cluster ON public.mine_cluster
	USING btree
	(
	  id
	);
-- ddl-end --

-- object: mine_cluster_fk | type: CONSTRAINT --
-- ALTER TABLE public.mine_point DROP CONSTRAINT IF EXISTS mine_cluster_fk CASCADE;
ALTER TABLE public.mine_point ADD CONSTRAINT mine_cluster_fk FOREIGN KEY (id_mine_cluster)
REFERENCES public.mine_cluster (id) MATCH FULL
ON DELETE RESTRICT ON UPDATE CASCADE;
-- ddl-end --

-- object: mine_cluster_fk | type: CONSTRAINT --
-- ALTER TABLE public.mine_polygon DROP CONSTRAINT IF EXISTS mine_cluster_fk CASCADE;
ALTER TABLE public.mine_polygon ADD CONSTRAINT mine_cluster_fk FOREIGN KEY (id_mine_cluster)
REFERENCES public.mine_cluster (id) MATCH FULL
ON DELETE RESTRICT ON UPDATE CASCADE;
-- ddl-end --

-- object: public.app_user | type: TABLE --
-- DROP TABLE IF EXISTS public.app_user CASCADE;
CREATE TABLE public.app_user(
	id char(7) NOT NULL,
	CONSTRAINT app_user_pk PRIMARY KEY (id)

);
-- ddl-end --
ALTER TABLE public.app_user OWNER TO postgres;
-- ddl-end --

-- object: app_user_fk | type: CONSTRAINT --
-- ALTER TABLE public.mine_polygon DROP CONSTRAINT IF EXISTS app_user_fk CASCADE;
ALTER TABLE public.mine_polygon ADD CONSTRAINT app_user_fk FOREIGN KEY (id_app_user)
REFERENCES public.app_user (id) MATCH FULL
ON DELETE RESTRICT ON UPDATE CASCADE;
-- ddl-end --

-- object: app_user_fk | type: CONSTRAINT --
-- ALTER TABLE public.mine_cluster DROP CONSTRAINT IF EXISTS app_user_fk CASCADE;
ALTER TABLE public.mine_cluster ADD CONSTRAINT app_user_fk FOREIGN KEY (id_app_user)
REFERENCES public.app_user (id) MATCH FULL
ON DELETE RESTRICT ON UPDATE CASCADE;
-- ddl-end --


-- Appended SQL commands --
GRANT CONNECT ON DATABASE vector_mine TO app;
GRANT SELECT ON mine_point TO app;
GRANT SELECT ON mine_cluster TO app;
GRANT SELECT ON app_user TO app;
GRANT SELECT, INSERT, DELETE ON mine_polygon TO app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app;
---
