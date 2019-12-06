# -*- coding: utf-8 -*-
import logging

import click
import geopandas as gpd
import swisslandstats as sls
from slugify import slugify

from swiss_urbanization import settings


@click.command()
@click.argument('sls_filepath', type=click.Path(exists=True))
@click.argument('gmb_filepath', type=click.Path(exists=True))
@click.argument('agglom_slug')
@click.argument('extract_filepath', type=click.Path())
def main(sls_filepath, gmb_filepath, agglom_slug, extract_filepath):
    logger = logging.getLogger(__name__)
    logger.info("preparing agglom extracts for %s", agglom_slug)

    # read the land dataframe from the SLS dataset
    ldf = sls.read_csv(sls_filepath)

    # get the municipal boundaries that configure the agglomeration
    # ACHTUNG: we use contains because of `ANAME` codes such as "Basel (CH)"
    # and "Basel (CH/DE/FR)"
    gdf = gpd.read_file(gmb_filepath)
    agglom_geom = gdf[gdf['ANAME'].apply(slugify).str.contains(
        agglom_slug)]['geometry'].unary_union

    # crop the land dataframe to the extent of the agglomeration boundaries
    agglom_ldf = ldf.clip_by_geometry(agglom_geom, geometry_crs=gdf.crs)
    logger.info("cropped dataset to the agglom extent (%d) pixels",
                len(agglom_ldf))

    # reclassify
    extracts_urban = settings.EXTRACTS_URBAN
    extracts_nonurban = settings.EXTRACTS_NONURBAN
    extracts_nodata = settings.EXTRACTS_NODATA

    def urban_reclassify_sls(class_val):
        # function to apply column-wise to a 4-class (urban, agricultural,
        # forest, unproductive) column of a `sls.LandDataFrame`, i.e.,
        # 'AS85R_4', 'AS97R_4', 'AS09R_4' or 'AS18_4'
        if class_val == 1:
            return extracts_urban
        elif class_val in [2, 3]:
            return extracts_nonurban
        else:  # nodata and unproductive use (e.g., water)
            return extracts_nodata

    main_domains_columns = ldf.columns[ldf.columns.str.startswith('AS')
                                       & ldf.columns.str.endswith('_4')]
    for main_domains_column in main_domains_columns:
        # replace the '4' by a '2' (two classes: urban and non-urban)
        urban_nonurban_column = main_domains_column[:-1] + '2'
        agglom_ldf[urban_nonurban_column] = agglom_ldf[
            main_domains_column].apply(urban_reclassify_sls)
    logger.info("reclassified columns %s into urban/non-urban",
                str(main_domains_columns))

    # we will not dump (to the extract csv file) the more fine-grained land
    # use columns - we will just dump the urban/non-urban one (but we still
    # need to dump the other non-land use columns with the coordinates and
    # year data)
    agglom_ldf[agglom_ldf.columns[~agglom_ldf.columns.str.startswith('AS')
                                  | agglom_ldf.columns.str.
                                  endswith('2')]].to_csv(extract_filepath)
    logger.info("saved dump of land dataframe extract for %s to %s",
                agglom_slug, extract_filepath)


if __name__ == '__main__':
    log_fmt = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    logging.basicConfig(level=logging.INFO, format=log_fmt)

    main()
