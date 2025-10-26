import os

try:
    __import__('neuromaps')
except ModuleNotFoundError:
    print(f'Package neuromaps is NOT available. Please install the Python package neuromaps before continuing.')

warnings = __import__('warnings')
warnings.filterwarnings("ignore")

from neuromaps.datasets import fetch_annotation

neuromaps_folder = os.path.join(data_dir,'NT','neuromaps')

fetch_annotation(tags='PET',space="MNI152", data_dir=neuromaps_folder, verbose=1)
