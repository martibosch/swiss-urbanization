# -*- coding: utf-8 -*-
import logging
import os
import sys
from os import path
from pathlib import Path

import boto3
import botocore
import click
from boto3.s3.transfer import TransferConfig
from dotenv import find_dotenv, load_dotenv
from tqdm import tqdm


@click.command()
@click.argument('clc_basename')
@click.argument('output_filepath', type=click.Path())
def main(clc_basename, output_filepath):
    logger = logging.getLogger(__name__)

    # callback to display a tqdm progress bar for file downloads
    def hook(t):
        def inner(bytes_amount):
            t.update(bytes_amount)

        return inner

    # Large zip files (e.g. for CLC datasets at 100m resolution) getcorrupted
    # when downloaded via boto3. Workaround: disable threads. See:
    # - https://github.com/spulec/moto/issues/816
    # - https://stackoverflow.com/questions/53210996/ ...
    #   ... how-to-get-working-zip-after-boto3-multipart-zip-download
    config = TransferConfig(use_threads=False)  # noqa

    # environment variables with S3 connection information
    session = boto3.Session(profile_name=os.environ.get('S3_PROFILE_NAME'))
    client = session.client(
        's3',
        # if using DigitalOcean Spaces instead of AWS S3
        endpoint_url=os.environ.get('S3_ENDPOINT_URL'),
    )
    BUCKET_NAME = os.environ.get('S3_BUCKET_NAME')

    logger.info(f'downloading CLC datasets from {BUCKET_NAME}')

    # UGLY HARDCODED ZIP FILENAMES (but some clc zip files end with `5a`
    # whereas others just with `5`)
    CLC_BASENAME_KEY_DICT = {
        '00': 'g100_clc00_V18_5.zip',
        '06': 'g100_clc06_V18_5a.zip',
        '12': 'g100_clc12_V18_5a.zip'
    }
    key = path.join('clc', CLC_BASENAME_KEY_DICT[clc_basename])

    try:
        logger.info(f'downloading key {key}')
        filesize = client.head_object(
            Bucket=BUCKET_NAME, Key=key)['ContentLength']
        # path to download the file to. Since it is a zip file that will be
        # deleted right after extracting its contents, we will just download
        # it to `basename` (e.g., g100_clc00_V18_5) in the current dir
        with tqdm(total=filesize, unit='B', unit_scale=True, desc=key) as t:
            client.download_file(
                BUCKET_NAME, key, output_filepath, Callback=hook(t))
            logger.info(f'file {key} successfully downloaded to '
                        f'{output_filepath}')
    except botocore.exceptions.ClientError as e:
        if e.response['Error']['Code'] == "404":
            logger.exception("the object does not exist.")
            sys.exit(1)
        else:
            raise
    except botocore.exceptions.IncompleteReadError as e:
        logger.exception(e)
        sys.exit(1)


if __name__ == '__main__':
    log_fmt = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    logging.basicConfig(level=logging.INFO, format=log_fmt)

    # not used in this stub but often useful for finding various files
    project_dir = Path(__file__).resolve().parents[2]

    # find .env automagically by walking up directories until it's found, then
    # load up the .env entries as environment variables
    load_dotenv(find_dotenv())

    main()
