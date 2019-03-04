# -*- coding: utf-8 -*-
import logging
from pathlib import Path
from urllib import request

import click

from dotenv import find_dotenv, load_dotenv

# https://www.bfs.admin.ch/bfs/fr/home/services/geostat/geodonnees-statistique-federale/limites-administratives/limites-communales-generalisees.assetdetail.5247306.html
#
BOUNDARIES_URI = 'https://www.bfs.admin.ch/bfsstatic/dam/assets/5247306/master'


@click.command()
@click.argument('output_filepath', type=click.Path())
def main(output_filepath):
    logger = logging.getLogger(__name__)

    # download zip
    logger.info(f'downloading administrative boundaries to {output_filepath}')
    # TODO: with tqdm(total=filesize, unit='B', unit_scale=True, desc=key) as t
    request.urlretrieve(BOUNDARIES_URI, output_filepath)


if __name__ == '__main__':
    log_fmt = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    logging.basicConfig(level=logging.INFO, format=log_fmt)

    # not used in this stub but often useful for finding various files
    project_dir = Path(__file__).resolve().parents[2]

    # find .env automagically by walking up directories until it's found, then
    # load up the .env entries as environment variables
    load_dotenv(find_dotenv())

    main()
