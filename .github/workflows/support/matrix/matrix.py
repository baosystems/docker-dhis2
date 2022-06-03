import boto3
import json
from packaging.version import Version

########

# Configuration

s3_bucket='releases.dhis2.org'

########

# Initialization

# Initialize the full matrix dict; include "dev" manually as it is not added below
full_matrix={
    'dhis2_version': ['dev'],
    'latest_major': [False],
    'latest_overall': [False],
    'include': [],
}

# Use boto3 without credentials (https://stackoverflow.com/a/34866092)
from botocore import UNSIGNED
from botocore.client import Config
s3 = boto3.client('s3', region_name='eu-west-1', config=Config(signature_version=UNSIGNED))

########

# List all top-level folders in S3 bucket (https://stackoverflow.com/a/54834746)
# DHIS2 versions will start with "2."; capture versions greater than 2.34

dhis2_majors=[]

s3_paginator = s3.get_paginator('list_objects')

pages = s3_paginator.paginate(Bucket=s3_bucket, Delimiter='/')

for prefix in pages.search('CommonPrefixes'):

    bucket_folder = prefix['Prefix'].strip("/")

    # Dev versions go straight to the version matrix
    if bucket_folder.startswith('2.') and Version(bucket_folder) > Version('2.34'):
        full_matrix['dhis2_version'].append(f'{bucket_folder}-dev')

    # Released versions
    if bucket_folder.startswith('2.') and Version(bucket_folder) > Version('2.34'):
        dhis2_majors.append(bucket_folder)

# Sort list of major releases by semver
dhis2_majors_sorted=sorted(dhis2_majors, key=lambda x: Version(x))

# Store all versions as dict of lists
dhis2_versions = {}

for dhis2_major in dhis2_majors_sorted:
    # Get all objects in bucket that start with "{dhis2_major}/dhis2-stable-"
    s3_prefix=f'{dhis2_major}/dhis2-stable-'

    dhis2_major_versions = []
    for page in s3_paginator.paginate(Bucket=s3_bucket):
        for object in page['Contents']:
            # Exclude objects that contain the "-eos/-latest/-rc" strings in the key name
            if (
                object['Key'].startswith(s3_prefix) and
                not any(key in object['Key'] for key in ("-eos", "-hidden", "-latest", "-rc"))
            ):
                # With the key name, remove text from the beginning and end so it's only a version name
                dhis2_version_semver = object['Key'].removeprefix(s3_prefix).removesuffix('.war').removesuffix('-EMBARGOED')
                # Add the cleaned up version string to the list
                dhis2_major_versions.append(dhis2_version_semver)

    # Remove duplicate entries from the list
    dhis2_major_versions_distinct = list(set(dhis2_major_versions))

    # Sort the list by semantic version
    dhis2_major_versions_sorted = sorted(dhis2_major_versions_distinct, key=lambda x: Version(x))

    # Add unique list to dhis2_versions dict
    dhis2_versions[dhis2_major] = dhis2_major_versions_sorted

# Remove major versions that have no stable releases (list of releases is empty)
# Useful for when a version of DHIS2 is in development with no releases
# (Using list() to allow editing dict while iterating; see https://stackoverflow.com/a/11941855)
for key, values in list(dhis2_versions.items()):
    if not values:
        del dhis2_versions[key]

for major, versions in dhis2_versions.items():

    # Loop each unique version, from oldest to newest, sort above
    for version in versions:

        # If the version is the latest within the major release, build a dictionary with non-default properties
        if version == dhis2_versions[major][-1]:

            # Start item with the default properties but with latest_major set to True
            matrix_item = {
                'dhis2_version': version,
                'latest_major': True,
                'latest_overall': False,
            }

            # Set as the latest overall version if also the latest within the latest major
            if major == sorted(list(dhis2_versions.keys()), key=lambda x: Version(x))[-1]:
                matrix_item['latest_overall'] = True

            # Add the dictionary to the "include" list of non-default DHIS2 versions
            full_matrix['include'].append(matrix_item)

        else:
            # Add the DHIS2 version to the dhis2_version list with no non-default properties
            full_matrix['dhis2_version'].append(version)

# Send list to stdout as JSON
print(json.dumps(full_matrix))
