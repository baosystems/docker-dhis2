import boto3
import json
from packaging.version import Version

########

# Configuration

s3_bucket='releases.dhis2.org'

########

# Initialization

# Initialize the full matrix dict
full_matrix={
    'dhis2_version': [],
    'latest_overall': [False],
    'include': [],
}

# Use boto3 without credentials (https://stackoverflow.com/a/34866092)
from botocore import UNSIGNED
from botocore.client import Config
s3 = boto3.client('s3', region_name='eu-west-1', config=Config(signature_version=UNSIGNED))

########

# List all top-level folders in S3 bucket (https://stackoverflow.com/a/54834746)
# DHIS2 versions will start with "2."; capture versions greater that 2.34

dhis2_majors=[]

s3_paginator = s3.get_paginator('list_objects')

pages = s3_paginator.paginate(Bucket=s3_bucket, Delimiter='/')

for prefix in pages.search('CommonPrefixes'):

    bucket_folder = prefix['Prefix'].strip("/")

    if bucket_folder.startswith('2.') and Version(bucket_folder) > Version('2.34'):
        # print(f'[DEBUG] bucket_folder={bucket_folder}')
        full_matrix['dhis2_version'].append(f'{bucket_folder}-dev')

# Include "dev" as the overall latest (used for determining type of GHA cache)
full_matrix['include'].append({
    'dhis2_version': 'dev',
    'latest_overall': True,
})

# Send list to stdout as JSON
print(json.dumps(full_matrix))

