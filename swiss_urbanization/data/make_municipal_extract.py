# -*- coding: utf-8 -*-
import logging
from pathlib import Path

import click
import geopandas as gpd
import numpy as np
import rasterio as rio
import rasterio.mask as rio_mask
import rasterio.windows as rio_windows
import scipy.ndimage as ndi
from dotenv import find_dotenv, load_dotenv
from slugify import slugify

from swiss_urbanization.data import settings, utils


@click.command()
@click.argument('boundaries_filepath', type=click.Path(exists=True))
@click.argument('municipal_slug')
@click.argument('input_filepath', type=click.Path(exists=True))
@click.argument('output_filepath', type=click.Path())
@click.option('--buffer-dist', required=False, default=100, type=float)
def main(boundaries_filepath,
         municipal_slug,
         input_filepath,
         output_filepath,
         buffer_dist=200):
    logger = logging.getLogger(__name__)
    logger.info(f'preparing municipal extracts for {input_filepath} and '
                f'{municipal_slug}')

    gdf = gpd.read_file(boundaries_filepath)

    with rio.open(input_filepath) as src:
        # get the municipal boundary
        municipal_gser = gdf[gdf['GMDNAME'].apply(slugify) == municipal_slug][
            'geometry']
        # ugly trick since in some years, `src.nodata` is 255 and in other it
        # is `None`. The variable `input_data` will take the first (from left
        # to right) non-None value, so if not None, `src.nodata` has priority
        input_nodata = src.nodata or settings.CLC_NODATA
        # We want to extract the urban patches that intersect the municipal
        # boundaries. This is done in the following 7 steps:
        # 1. Get municipal extent mask (we will not use `crop=True`) because
        #    this would trim the intersecting patches
        # ACHTUNG: `img` will be of shape (1, width, height)
        img, _ = rio_mask.mask(
            src, municipal_gser.to_crs(src.crs), nodata=input_nodata)
        municipal_extent_mask = img[0] != input_nodata
        # 2. Reclassify the CLC values of the whole landscape into a binary
        #    urban/non-urban array
        # reclassify it into urban/non-urban LULC
        # we will just consider urban pixels, the rest will be considered as
        # `nodata`, which is why `output_nodata` is the third argument
        # (instead of an arbitrary value to denonte non-urban classes)
        urban_arr = utils.urban_reclassify_clc(
            src.read(1), settings.EXTRACTS_URBAN, settings.EXTRACTS_NONURBAN,
            input_nodata, settings.EXTRACTS_NODATA)
        # 3. Get labelled urban features of the reclassified array
        label_arr, _ = ndi.label(
            urban_arr == settings.EXTRACTS_URBAN,
            structure=ndi.generate_binary_structure(2, 2))
        # 4. Get the labels of the features (urban patches) that intersect the
        #    municipal boundaries
        extent_labels = np.delete(
            np.unique(np.where(municipal_extent_mask, label_arr, 0)), 0)
        # 5. Get a mask for the extent of the untrimmed patches that intersect
        # the municipal boundaries, plus an arbitrary buffer
        iterations = int(buffer_dist / src.res[0])
        if iterations < 1:
            iterations = 1
        extent_mask = ndi.binary_dilation(
            np.isin(label_arr, extent_labels), iterations=iterations)
        # 6. Get the bounds of the extent mask
        rows, cols = ndi.find_objects(extent_mask)[0]
        # 7. Get the output array
        output_arr = np.where(extent_mask, urban_arr,
                              settings.EXTRACTS_NODATA)[rows, cols]

        # Get some necessary metadata to write the extract
        output_height, output_width = output_arr.shape
        output_transform = src.window_transform(
            rio_windows.Window(cols.start, rows.start, output_width,
                               output_height))

        # update the keyword arguments to ouptut the extract as a GeoTiff
        kwargs = src.meta.copy()
        output_dtype = rio.uint8
        kwargs.update({
            'dtype': output_dtype,
            'width': output_width,
            'height': output_height,
            'transform': output_transform,
            'nodata': settings.EXTRACTS_NODATA
        })
        logger.info(
            f'writing extract of shape {output_arr.shape} to {output_filepath}'
        )
        with rio.open(output_filepath, 'w', **kwargs) as dst:
            dst.write(output_arr.astype(output_dtype), 1)


if __name__ == '__main__':
    log_fmt = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    logging.basicConfig(level=logging.INFO, format=log_fmt)

    # not used in this stub but often useful for finding various files
    project_dir = Path(__file__).resolve().parents[2]

    # find .env automagically by walking up directories until it's found, then
    # load up the .env entries as environment variables
    load_dotenv(find_dotenv())

    main()
