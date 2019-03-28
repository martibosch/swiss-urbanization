# -*- coding: utf-8 -*-
import logging
from pathlib import Path

import click
import geopandas as gpd
import rasterio as rio
import rasterio.mask as rio_mask
from dotenv import find_dotenv, load_dotenv
from slugify import slugify

from swiss_urbanization.data import settings, utils


@click.command()
@click.argument('boundaries_filepath', type=click.Path(exists=True))
@click.argument('agglomeration_slug')
@click.argument('input_filepath', type=click.Path(exists=True))
@click.argument('output_filepath', type=click.Path())
def main(boundaries_filepath, agglomeration_slug, input_filepath,
         output_filepath):
    logger = logging.getLogger(__name__)
    logger.info(f'preparing agglomeration extracts for {input_filepath} and '
                f'{agglomeration_slug}')

    gdf = gpd.read_file(boundaries_filepath)

    with rio.open(input_filepath) as src:
        # get the municipal boundaries that configure the agglomeration
        # ACHTUNG: we use contains because of `ANAME` codes such as "Basel
        # (CH)" and "Basel (CH/DE/FR)"
        agglomeration_gser = gdf[gdf['ANAME'].apply(slugify).str.contains(
            agglomeration_slug)]['geometry']
        # ugly trick since in some years, `src.nodata` is 255 and in other it
        # is `None`. The variable `input_data` will take the first (from left
        # to right) non-None value, so if not None, `src.nodata` has priority
        input_nodata = src.nodata or settings.CLC_NODATA
        # get only the subset of the LULC raster that falls within the
        # above boundaries
        img, transform = rio_mask.mask(
            src,
            agglomeration_gser.to_crs(src.crs),
            crop=True,
            nodata=input_nodata)
        # reclassify it into urban/non-urban LULC
        # ACHTUNG: `img` will be of shape (1, width, height)
        output_arr = utils.urban_reclassify_clc(img[0])

        output_height, output_width = output_arr.shape

        # update the keyword arguments to ouptut the urban extract as a GeoTiff
        kwargs = src.meta.copy()
        output_dtype = rio.uint8
        kwargs.update({
            'dtype': output_dtype,
            'width': output_width,
            'height': output_height,
            'transform': transform,
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
