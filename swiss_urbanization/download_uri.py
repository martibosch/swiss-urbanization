import logging
from urllib import request

import click


@click.command()
@click.argument('uri')
@click.argument('dst_filepath', type=click.Path())
def main(uri, dst_filepath):
    logger = logging.getLogger(__name__)

    # download zip
    logger.info("downloading %s to %s", uri, dst_filepath)
    # TODO: with tqdm(total=filesize, unit='B', unit_scale=True, desc=key) as t
    request.urlretrieve(uri, dst_filepath)
    logger.info("done")


if __name__ == '__main__':
    log_fmt = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    logging.basicConfig(level=logging.INFO, format=log_fmt)

    main()
