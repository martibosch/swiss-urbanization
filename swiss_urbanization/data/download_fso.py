# -*- coding: utf-8 -*-
import logging
from urllib import request

import click


@click.command()
@click.argument('uri')
@click.argument('output_filepath', type=click.Path())
def main(uri, output_filepath):
    logger = logging.getLogger(__name__)

    # download zip
    logger.info(f'downloading {uri} to {output_filepath}')
    # TODO: with tqdm(total=filesize, unit='B', unit_scale=True, desc=key) as t
    request.urlretrieve(uri, output_filepath)


if __name__ == '__main__':
    log_fmt = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    logging.basicConfig(level=logging.INFO, format=log_fmt)

    main()
