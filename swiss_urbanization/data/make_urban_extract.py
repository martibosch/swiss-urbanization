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
def main(boundaries_filepath, agglomeration_slug, input_filepath,
         output_filepath):
    logger = logging.getLogger(__name__)
    logger.info(f'preparing urban extracts for {input_filepath} and '
                f'{agglomeration_slug}')

    gdf = gpd.read_file(boundaries_filepath)

    def _urban_reclassify_corine(landscape_arr,
                                 urban_class=1,
                                 non_urban_class=2,
                                 nodata=0):
        # function to reclassify CLC codes into urban/non-urban
        arr = np.copy(landscape_arr)
        arr[(arr >= 1) & (arr <= 11)] = urban_class
        arr[(arr != 1) & (arr != 255)] = non_urban_class
        arr[arr == 255] = nodata

        return arr

    with rio.open(input_filepath) as src:
        # get the municipal boundaries that configure the agglomeration
        # ACHTUNG: we use contains because of `ANAME` codes such as "Basel
        # (CH)" and "Basel (CH/DE/FR)"
        agglomeration_gser = gdf[gdf['ANAME'].apply(slugify).str.contains(
            agglomeration_slug)]['geometry']
        # get only the subset of the LULC raster that falls within the
        # above boundaries
        img, transform = rio_mask.mask(
            src, agglomeration_gser.to_crs(src.crs), crop=True)
        # reclassify it into urban/non-urban LULC
        # ACHTUNG: `img` will be of shape (1, width, height)
        urban_arr = _urban_reclassify_corine(img[0])
        # update the keyword arguments to ouptut the urban extract as a GeoTiff
        height, width = urban_arr.shape
        kwargs = src.meta.copy()
        out_dtype = rio.uint8
        kwargs.update({
            'dtype': out_dtype,
            'width': width,
            'height': height,
            'transform': transform,
            'nodata': 0
        })
        logger.info(
            f'writing extract of shape {urban_arr.shape} to {output_filepath}')
        with rio.open(output_filepath, 'w', **kwargs) as dst:
            dst.write(urban_arr.astype(out_dtype), 1)


if __name__ == '__main__':
    log_fmt = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    logging.basicConfig(level=logging.INFO, format=log_fmt)

    # not used in this stub but often useful for finding various files
    project_dir = Path(__file__).resolve().parents[2]

    # find .env automagically by walking up directories until it's found, then
    # load up the .env entries as environment variables
    load_dotenv(find_dotenv())

    main()
