import json
import logging
from os import path

import click
import numpy as np
import pwlf
import pylandstats as pls
import swisslandstats as sls

from swiss_urbanization import settings, utils


@click.command()
@click.argument('agglom_csv_filepath', type=click.Path(exists=True))
@click.argument('dst_filepath', type=click.Path())
def main(agglom_csv_filepath, dst_filepath):
    logger = logging.getLogger(__name__)
    logger.info("extracting breakpoints from %s", agglom_csv_filepath)

    agglom_slug = path.splitext(path.basename(agglom_csv_filepath))[0]

    # read the land dataframe from the SLS dataset
    ldf = sls.read_csv(agglom_csv_filepath)
    crs = ldf.crs
    transform = ldf.get_transform()

    # get LULC values
    urban_class = settings.EXTRACTS_URBAN
    nodata = settings.EXTRACTS_NODATA

    # get the base mask and buffer distances
    base_mask = settings.BASE_MASK_DICT[agglom_slug]
    base_mask_crs = settings.BASE_MASK_CRS
    buffer_dists = settings.BUFFER_DISTS

    # init landscapes
    landscapes, _ = utils.get_landscapes_and_dates(ldf, nodata)

    breakpoints = []
    for landscape in landscapes:
        ba = pls.BufferAnalysis(landscape,
                                base_mask,
                                buffer_dists=buffer_dists,
                                base_mask_crs=base_mask_crs,
                                landscape_crs=crs,
                                landscape_transform=transform)
        total_area_ser = ba.compute_class_metrics_df(
            metrics=['total_area'],
            classes=[urban_class]).loc[urban_class]['total_area']

        x, y = np.log(total_area_ser.index.values), np.log(
            total_area_ser.values)
        pw = pwlf.PiecewiseLinFit(x, y)
        pw_res = pw.fit(2)
        breakpoints.append(np.exp(pw_res[1]))

    with open(dst_filepath, 'w') as fp:
        json.dump(breakpoints, fp)
    logger.info("dumped breakpoints to %s", dst_filepath)


if __name__ == '__main__':
    log_fmt = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    logging.basicConfig(level=logging.INFO, format=log_fmt)

    main()
