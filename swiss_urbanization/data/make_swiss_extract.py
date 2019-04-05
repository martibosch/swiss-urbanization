import logging
from pathlib import Path

import click
import geopandas as gpd
import numpy as np
import rasterio as rio
import rasterio.warp as rio_warp
import rasterio.windows as rio_windows
from dotenv import find_dotenv, load_dotenv

from swiss_urbanization.data import settings, utils


@click.command()
@click.argument('boundaries_filepath', type=click.Path(exists=True))
@click.argument('input_filepath', type=click.Path(exists=True))
@click.argument('output_filepath', type=click.Path())
@click.argument('dst_crs', default='epsg:3035')
@click.argument('buffer_dist', default=1000)
def main(boundaries_filepath, input_filepath, output_filepath, dst_crs,
         buffer_dist):
    logger = logging.getLogger(__name__)
    logger.info(
        f'cropping {input_filepath} to the extent of {boundaries_filepath}')

    gdf = gpd.read_file(boundaries_filepath)

    with rio.open(input_filepath) as src:
        # get src crs
        src_crs = src.crs
        # transform the geometry to utm crs so the buffer is applied in meters.
        # Then project the geometry to the raster's crs in order to apply the
        # mask. The `buffer_dist` in meters trick inspired by
        # https://github.com/gboeing/osmnx/blob/master/osmnx/core.py
        # calculate the centroid of the union of all the geometries in the
        avg_longitude = gdf.to_crs({
            'init': 'epsg:4326'
        })['geometry'].unary_union.centroid.x
        utm_zone = int(np.floor((avg_longitude + 180) / 6.) + 1)
        utm_crs = {
            'datum': 'WGS84',
            'ellps': 'WGS84',
            'proj': 'utm',
            'zone': utm_zone,
            'units': 'm'
        }
        # bounds of the buffered geometry
        bounds = gdf.to_crs(utm_crs)['geometry'].buffer(buffer_dist).to_crs(
            src_crs).total_bounds

        # get a window for the bounds of the buffered geometry and get its
        # corresponding array and transform
        window = rio_windows.from_bounds(*bounds, src.transform)
        window_arr = src.read(1, window=window)
        window_transform = src.window_transform(window)

        # see if we need to reproject (capitalize strings to ensure equality
        # of, e.g., 'epsg:3035' and 'EPSG:3035'
        if dst_crs.upper() == src_crs.to_string().upper():
            arr = window_arr
            transform = window_transform
            width = window.width
            height = window.height
        else:
            # reproject window to dst_crs
            logger.info(
                f'reprojecting cropped window from {src_crs} to {dst_crs}')

            transform, width, height = rio_warp.calculate_default_transform(
                src_crs, dst_crs, window_arr.shape[1], window_arr.shape[0],
                *bounds)
            # init empty destination array
            arr = np.ndarray((height, width), dtype=window_arr.dtype)
            # reproject
            rio_warp.reproject(
                window_arr,
                arr,
                src_transform=window_transform,
                src_crs=src_crs,
                dst_transform=transform,
                dst_crs=dst_crs,
                resampling=rio_warp.Resampling.nearest)

        # reclassify the array into urban/non-urban classes
        dst_arr = utils.urban_reclassify_clc(arr)
        dst_dtype = rio.uint8

        kwargs = src.meta.copy()
        kwargs.update({
            'crs': dst_crs,
            'transform': transform,
            'width': width,
            'height': height,
            'dtype': dst_dtype,
            'nodata': settings.EXTRACTS_NODATA
        })

        with rio.open(output_filepath, 'w', **kwargs) as dst:
            logger.info(f'writing cropped and reprojected raster of shape '
                        f'{arr.shape} to {output_filepath}')
            dst.write(dst_arr.astype(dst_dtype), 1)


if __name__ == '__main__':
    log_fmt = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    logging.basicConfig(level=logging.INFO, format=log_fmt)

    # not used in this stub but often useful for finding various files
    project_dir = Path(__file__).resolve().parents[2]

    # find .env automagically by walking up directories until it's found, then
    # load up the .env entries as environment variables
    load_dotenv(find_dotenv())

    main()
