# -*- coding: utf-8 -*-
import logging
from pathlib import Path

import click
import numpy as np
from dotenv import find_dotenv, load_dotenv

import geopandas as gpd
import rasterio as rio
import rasterio.mask as rio_mask
from slugify import slugify


@click.command()
@click.argument('boundaries_filepath', type=click.Path(exists=True))
@click.argument('agglomeration_slug')
@click.argument('input_filepath', type=click.Path(exists=True))
@click.argument('output_filepath', type=click.Path())
@click.option('--input-nodata', required=False, default=None, type=int)
@click.option('--output-nodata', required=False, default=0, type=int)
def main(boundaries_filepath, agglomeration_slug, input_filepath,
         output_filepath, input_nodata, output_nodata):
    logger = logging.getLogger(__name__)
    logger.info(f'preparing agglomeration extracts for {input_filepath} and '
                f'{agglomeration_slug}')

    gdf = gpd.read_file(boundaries_filepath)

    def _urban_reclassify_corine(landscape_arr, urban_class, non_urban_class,
                                 input_nodata, output_nodata):
        # function to reclassify CLC codes into urban/non-urban
        arr = np.copy(landscape_arr)
        arr[(arr >= 1) & (arr <= 11)] = urban_class
        arr[(arr != 1) & (arr != input_nodata)] = non_urban_class
        arr[arr == input_nodata] = output_nodata

        return arr

    with rio.open(input_filepath) as src:
        # get the municipal boundaries that configure the agglomeration
        # ACHTUNG: we use contains because of `ANAME` codes such as "Basel
        # (CH)" and "Basel (CH/DE/FR)"
        agglomeration_gser = gdf[gdf['ANAME'].apply(slugify).str.contains(
            agglomeration_slug)]['geometry']
        # ugly trick since in some years, `src.nodata` is 255 and in other it
        # is `None`
        input_nodata = input_nodata or src.nodata
        # get only the subset of the LULC raster that falls within the
        # above boundaries
        img, transform = rio_mask.mask(
            src,
            agglomeration_gser.to_crs(src.crs),
            crop=True,
            nodata=input_nodata)
        # reclassify it into urban/non-urban LULC
        # ACHTUNG: `img` will be of shape (1, width, height)
        output_arr = _urban_reclassify_corine(img[0], 1, 2, input_nodata,
                                              output_nodata)

        output_height, output_width = output_arr.shape

        # update the keyword arguments to ouptut the urban extract as a GeoTiff
        kwargs = src.meta.copy()
        output_dtype = rio.uint8
        kwargs.update({
            'dtype': output_dtype,
            'width': output_width,
            'height': output_height,
            'transform': transform,
            'nodata': output_nodata
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
