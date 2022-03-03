import json
from packaging.version import Version

# Packages not built-in
import html2text
import requests
import xmltodict

########

# Initialize the full matrix dict
full_matrix={
    'dhis2_version': [],
    'latest_major': [False],
    'latest_overall': [False],
    'include': [],
}

########

# Configure options for html2text
# https://github.com/Alir3z4/html2text/blob/master/docs/usage.md
text_maker = html2text.HTML2Text()
text_maker.body_width = "10"
text_maker.ignore_images = True
text_maker.ignore_images = True
text_maker.single_line_break = True

# Get HTML from releases.dhis2.org and convert to text
page_response = requests.get('https://s3-eu-west-1.amazonaws.com/releases.dhis2.org/index.html')
page_raw = html2text.html2text(page_response.text)

# Get the line containing DHIS2 major releases, remove text before and after, create a list from string separated by spaces
line_raw = [i for i in page_raw.splitlines() if "DHIS 2 version" in i][0]
line_trimmed = line_raw.removeprefix('DHIS 2 version ').removesuffix(' dev stable canary')
dhis2_majors = line_trimmed.split(' ')

# Limit to 2.35 and up (compatible with Java 11)
dhis2_majors_trimmed=[dhis2_major for dhis2_major in dhis2_majors if Version(dhis2_major) > Version('2.34')]

# Sort list of major releases by semver
dhis2_majors_sorted=sorted(dhis2_majors_trimmed, key=lambda x: Version(x))

########

for dhis2_major in dhis2_majors_sorted:

    # Retrieve objects from the public S3 bucket filtered by an object prefix for the major release, eg: "2.35/dhis2-stable-"
    s3_payload = {
        'prefix': f'{dhis2_major}/dhis2-stable-'
    }
    s3_response = requests.get('https://s3-eu-west-1.amazonaws.com/releases.dhis2.org/', params=s3_payload)

    # Convert the XML response from S3 to a dict
    parsed = xmltodict.parse(s3_response.content)

    # Skip this version if bucket prefix exists for a version without any applicable S3 objects
    # This first appeared when 2.38 had dev releases but no stable releases
    if 'Contents' not in parsed['ListBucketResult']:
        continue

    # Within the major release, add all S3 objects where the key (file name) does not contain "-eos"/"-latest"/"-rc" to list
    dhis2_versions = []
    for s3_object in parsed['ListBucketResult']['Contents']:
        # Exclude objects that contains the strings in the key name
        if not any(value in s3_object['Key'] for value in ("-eos", "-latest", "-rc")):
            # With the key name, remove text from the beginning and end so it's only a version name
            dhis2_version_semver = s3_object['Key'].removeprefix(s3_payload['prefix']).removesuffix('.war').removesuffix('-EMBARGOED')
            # Add the cleaned up version string to the list
            dhis2_versions.append(dhis2_version_semver)

    # Remove duplicate entries from the list
    dhis2_versions_distinct = list(set(dhis2_versions))
    # Sort the list by semantic version
    dhis2_versions_sorted = sorted(dhis2_versions_distinct, key=lambda x: Version(x))

    # Loop each unique version, from oldest to newest
    for dhis2_version in dhis2_versions_sorted:

        # If the version is the latest within the major release, build a dictionary with non-default properties
        if dhis2_version == dhis2_versions_sorted[-1]:

            # Start item with the default properties but with latest_major set to True
            matrix_item = {
                'dhis2_version': dhis2_version,
                'latest_major': True,
                'latest_overall': False,
            }

            # Set as the latest overall version if also the latest within the latest major
            if dhis2_major == dhis2_majors_sorted[-1]:
                matrix_item['latest_overall'] = True

            # Add the dictionary to the "include" list of non-default DHIS2 versions
            full_matrix['include'].append(matrix_item)

        else:
            # Add the DHIS2 version to the dhis2_version list with no non-default properties
            full_matrix['dhis2_version'].append(dhis2_version)

print(json.dumps(full_matrix))
