import os

from dotenv import find_dotenv, load_dotenv

load_dotenv(find_dotenv())

CLC_NODATA = os.environ.get('CLC_NODATA', 255)
EXTRACTS_URBAN = os.environ.get('EXTRACTS_URBAN', 1)
EXTRACTS_NONURBAN = os.environ.get('EXTRACTS_NONURBAN', 2)
EXTRACTS_NODATA = os.environ.get('EXTRACTS_NODATA', 0)
