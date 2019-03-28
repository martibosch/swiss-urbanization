import os

from dotenv import find_dotenv, load_dotenv

load_dotenv(find_dotenv())

CLC_URBAN = os.environ.get('CLC_URBAN', (1, 11))
# CLC codes from 35 to 44 denote wetlands and water bodies that we rather
# consider as 'nodata'
CLC_NONURBAN = os.environ.get('CLC_NONURBAN', (12, 34))
CLC_NODATA = os.environ.get('CLC_NODATA', 255)
EXTRACTS_URBAN = os.environ.get('EXTRACTS_URBAN', 1)
EXTRACTS_NONURBAN = os.environ.get('EXTRACTS_NONURBAN', 2)
EXTRACTS_NODATA = os.environ.get('EXTRACTS_NODATA', 0)
