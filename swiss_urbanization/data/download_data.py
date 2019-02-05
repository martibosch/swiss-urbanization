# -*- coding: utf-8 -*-
import logging
import os
import sys
import zipfile
from os import path
from pathlib import Path
from urllib import request

import botocore
import click
from dotenv import find_dotenv, load_dotenv

import boto3
from boto3.s3.transfer import TransferConfig
from tqdm import tqdm

# https://www.bfs.admin.ch/bfs/fr/home/services/geostat/geodonnees-statistique-federale/limites-administratives/limites-communales-generalisees.assetdetail.5247306.html
#
BOUNDARIES_URI = 'https://www.bfs.admin.ch/bfsstatic/dam/assets/5247306/master'


@click.group()
@click.pass_context
def cli(ctx):
    logger = logging.getLogger(__name__)
    ctx.ensure_object(dict)
    ctx.obj['LOGGER'] = logger


@cli.command()
@click.pass_context
@click.argument('output_dir', type=click.Path())
def agglomeration_boundaries(ctx, output_dir):
    logger = ctx.obj['LOGGER']

    zip_filepath = output_dir + '.zip'

    # download zip
    logger.info(f'downloading administrative boundaries to {zip_filepath}')
    # TODO: with tqdm(total=filesize, unit='B', unit_scale=True, desc=key) as t
    request.urlretrieve(BOUNDARIES_URI, zip_filepath)

    # extract zip
    logger.info(f'extracting {zip_filepath} to {output_dir}')
    with zipfile.ZipFile(zip_filepath, 'r') as zip_ref:
        zip_ref.extractall(output_dir)

    # remove zip file
    logger.info(f'removing {zip_filepath}')
    os.remove(zip_filepath)


@cli.command()
@click.pass_context
@click.argument('year_code')
@click.argument('output_dir', type=click.Path())
def clc_dataset(ctx, year_code, output_dir):
    logger = ctx.obj['LOGGER']

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
        region_name=os.environ.get('S3_REGION_NAME'),
        endpoint_url=os.environ.get('S3_ENDPOINT_URL'),
    )
    BUCKET_NAME = os.environ.get('S3_BUCKET_NAME')

    logger.info(f'downloading CLC datasets from {BUCKET_NAME}')

    # UGLY HARDCODED FILENAMES (but some clc zip files end with `5a` whereas
    # others just with `5`
    CLC_YEAR_DATASET_DICT = {
        '00': 'g100_clc00_V18_5',
        '06': 'g100_clc06_V18_5a',
        '12': 'g100_clc12_V18_5a'
    }
    clc_dataset = CLC_YEAR_DATASET_DICT[year_code]

    try:
        # filename of the CLC file to be downloaded and respective S3
        # bucket key
        filename = clc_dataset + '.zip'
        key = path.join('clc', filename)
        logger.info(f'downloading key {key}')
        filesize = client.head_object(
            Bucket=BUCKET_NAME, Key=key)['ContentLength']
        # path to download the file to. Since it is a zip file that will be
        # deleted right after extracting its contents, we will just download
        # it to `filename` (e.g., g100_clc00_V18_5) in the current dir
        download_filepath = filename
        with tqdm(total=filesize, unit='B', unit_scale=True, desc=key) as t:
            client.download_file(
                BUCKET_NAME, key, download_filepath, Callback=hook(t))
            logger.info(f'file {filename} successfully downloaded to '
                        f'{download_filepath}')
    except botocore.exceptions.ClientError as e:
        if e.response['Error']['Code'] == "404":
            logger.exception("the object does not exist.")
            sys.exit(1)
        else:
            raise
    except botocore.exceptions.IncompleteReadError as e:
        logger.exception(e)
        sys.exit(1)

    # extract zip
    logger.info('extracting {} to {}'.format(download_filepath, output_dir))
    with zipfile.ZipFile(download_filepath, 'r') as zip_ref:
        zip_ref.extractall(output_dir)

    # remove zip file
    logger.info('removing zip file {}'.format(download_filepath))
    os.remove(download_filepath)


if __name__ == '__main__':
    log_fmt = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    logging.basicConfig(level=logging.INFO, format=log_fmt)

    # not used in this stub but often useful for finding various files
    project_dir = Path(__file__).resolve().parents[2]

    # find .env automagically by walking up directories until it's found, then
    # load up the .env entries as environment variables
    load_dotenv(find_dotenv())

    cli()
