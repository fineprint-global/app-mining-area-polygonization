#!/usr/bin/python
import sys
import argparse
import rasterio
import fiona
import numpy as np 
from shapely.geometry import shape, box, MultiPolygon
from rasterio import features
from affine import Affine
import multiprocessing
from functools import partial

# initiate the parser
parser = argparse.ArgumentParser()

# add long and short argument
parser.add_argument("--inputfile", "-i", help="set path to the input geometries. The input file must have polygons/multipolygons")
parser.add_argument("--outputfile", "-o", help="set path to output raster file")
parser.add_argument("--xmin", "-xmin", help="set the bounding coordinates of the output raster. The coordinates must have the same CRS as the input file")
parser.add_argument("--xmax", "-xmax", help="set the bounding coordinates of the output raster. The coordinates must have the same CRS as the input file")
parser.add_argument("--ymin", "-ymin", help="set the bounding coordinates of the output raster. The coordinates must have the same CRS as the input file")
parser.add_argument("--ymax", "-ymax", help="set the bounding coordinates of the output raster. The coordinates must have the same CRS as the input file")
parser.add_argument("--nrow", "-nrow", help="set number of rows of the output raster file")
parser.add_argument("--ncol", "-ncol", help="set number of columns of the output raster file")

# read arguments from the command line
args = parser.parse_args()

def _rasterize_geom(geom, dim, affine_trans, all_touched):
  out_array = features.rasterize(
    [(geom, 1)],
    out_shape   = dim,
    transform   = affine_trans,
    fill        = 0,
    all_touched = all_touched)
  return out_array

def _calculate_cell_coverage(idx, affine_trans, geom):
    # idx = (row, col)
    
    # Construct the geometry of grid cell from its boundaries
    window = ((idx[0], idx[0]+1), (idx[1], idx[1]+1))
    ((row_min, row_max), (col_min, col_max)) = window
    x_min, y_min = (col_min, row_max) * affine_trans
    x_max, y_max = (col_max, row_min) * affine_trans
    bounds = (x_min, y_min, x_max, y_max)
    cell = box(*bounds)

    # get the intersection between the cell and the polygons
    cell_intersection = cell.intersection(geom)

    # calculate the percentage of cell covered by the polygon
    cell_coverage = int(round(cell_intersection.area / cell.area * 100))

    return cell_coverage

if __name__ == "__main__":
   
   # convert arguments to numeric data types 
   # GDAL:   (c, a, b, f, d, e)
   # Affine: (a, b, c, d, e, f)
   xmin = float(args.xmin)
   xmax = float(args.xmax)
   ymin = float(args.ymin)
   ymax = float(args.ymax)
   dim = (int(args.nrow), int(args.ncol))
   dy = abs((ymax - ymin) / dim[0])
   dx = abs((xmax - xmin) / dim[1])
   affine_trans = Affine(dx, 0.0, xmin, 0.0, -dy, ymax)

   # open input geometries and transform to destination crs 
   feat = fiona.open(args.inputfile)

   # select featuers within bounding box
   print "Selecting featuers within bounding box"
   feat_intersecting = feat.filter(bbox=(xmin, ymin, xmax, ymax))
   geom = MultiPolygon([shape(pol['geometry']) for pol in feat_intersecting])
   
   if geom.is_empty:
      sys.exit("warning: Nothing to do. There are not geometries overlapping the bounding box. Check the bounding coordinates and the polygons CRS")
   
   profile = {
       'affine': affine_trans,
       'height': dim[0],
       'width': dim[1],
       'count': 1,
       'crs': {'init': feat.crs['init']},
       'driver': 'GTiff',
       'dtype': 'uint8',
       'compress': 'lzw',
       'nodata': None,
       'tiled': False,
       'transform': affine_trans}

   # fill grid cells intersecting polygons with 100% 
   print "Filling grid cells 100% coverd by polygons"
   perc_raster = _rasterize_geom(geom, dim, affine_trans, all_touched=True) * 100
   
   # get cells touching polygons borders 
   print "Selecting cells touching polygons borders"
   boundary = _rasterize_geom(geom.boundary, dim, affine_trans, all_touched=True)
   idx = zip(*np.where(boundary == 1))
   rows, cols = zip(*idx)
   
   # calculate percentage of coverage for cells touching polygons borders 
   num_cores = multiprocessing.cpu_count()
   print "Calculate percentage of coverage for", len(rows), "cells touching polygons borders using ", num_cores, " cores"
   # perc_raster[rows, cols] = Parallel(n_jobs=num_cores)(delayed(_calculate_cell_coverage)(i, j, affine_trans, geom) for i, j in idx)
   pool = multiprocessing.Pool(processes=num_cores)
   perc_raster[rows, cols] = pool.map(partial(_calculate_cell_coverage, affine_trans=affine_trans, geom=geom), idx)

   print "Writing results to ", args.outputfile
   with rasterio.open(args.outputfile, 'w', **profile) as dst:
       dst.write(perc_raster, 1)
