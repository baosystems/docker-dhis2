import json
from packaging.version import Version
import urllib3

########

# Initialization

# Initialize the full matrix dict
full_matrix={
    'dhis2_version': [],
    'java_major': ['11'],
    'latest_major': [False],
    'latest_overall': [False],
    'include': [],
}

# All released versions as dict of lists
dhis2_versions = {}

########

# Download DHIS2 releases information

http = urllib3.PoolManager()
stable_json_resp = http.request('GET', 'https://releases.dhis2.org/v1/versions/stable.json')
stable_json = json.loads(stable_json_resp.data)

########

# List of all major versions 2.35 and newer
dhis2_majors=[
    version['name']
    for version in stable_json['versions']
    if Version(version['name']) >= Version('2.35')
]

# Sort list of major releases by semver
dhis2_majors_sorted=sorted(dhis2_majors, key=lambda x: Version(x))

for dhis2_major in dhis2_majors_sorted:

    dhis2_major_versions = []

    # List of all patch versions within a major release version
    patch_versions = [i['patchVersions'] for i in stable_json['versions'] if i['name'] == dhis2_major][0]

    # Add the "name" value at the full version
    for patch_version in patch_versions:
        dhis2_major_versions.append(patch_version['name'])

    # Remove duplicate entries from the list
    dhis2_major_versions_distinct = list(set(dhis2_major_versions))

    # Sort the list by semantic version
    dhis2_major_versions_sorted = sorted(dhis2_major_versions_distinct, key=lambda x: Version(x))

    # Add unique and sorted list to dhis2_versions dict
    dhis2_versions[dhis2_major] = dhis2_major_versions_sorted

    # Add dev version to list of builds; versions v41 and up require Java 17
    if Version(dhis2_major) < Version('41'):
        full_matrix['dhis2_version'].append(f"{dhis2_major}-dev")
    else:
        full_matrix['include'].append({
            'dhis2_version': f"{dhis2_major}-dev",
            'java_major': '17',
            'latest_major': False,
            'latest_overall': False,
        })

    # Loop each release version, from oldest to newest
    for version in dhis2_major_versions_sorted:

        # Start item with the same properties as the default builds
        matrix_item = {
            'dhis2_version': version,
            'java_major': '11',
            'latest_major': False,
            'latest_overall': False,
        }

        # Major versions v41 and up require Java 17
        if Version(dhis2_major) >= Version('41'):
            matrix_item['java_major'] = '17'

        # If the version is the latest within the major release...
        if version == dhis2_major_versions_sorted[-1]:

            # Set as the latest version within the major
            matrix_item['latest_major'] = True

            # Set as the latest overall version if the latest within the latest major
            if dhis2_major == dhis2_majors_sorted[-1]:
                matrix_item['latest_overall'] = True

            # Add as a non-default build
            full_matrix['include'].append(matrix_item)

        # If the version is not the latest within the major release...
        else:

            if Version(dhis2_major) >= Version('41'):
                # Add a v41+ release to the list of non-default builds
                full_matrix['include'].append(matrix_item)

            else:
                # Add the release to the list of default builds
                full_matrix['dhis2_version'].append(version)

        # All 2.39 and 2.40 stable releases to include a Java 17 build
        if Version(dhis2_major) in (Version('2.39'), Version('2.40')):
            full_matrix['include'].append({
                'dhis2_version': version,
                'java_major': '17',
                'latest_major': False,
                'latest_overall': False,
            })

# # Include the dev release for the next major version as a Java 17 build
# # NOTE: Uncomment and/or edit logic once v41 builds are available
# dhis2_major_next = f"{Version(dhis2_majors_sorted[-1]).major+1}"
# full_matrix['include'].append({
#     'dhis2_version': f"{dhis2_major_next}-dev",
#     'java_major': '17',
#     'latest_major': False,
#     'latest_overall': False,
# })

# Include a Java 17 build for "dev"
full_matrix['include'].append({
    'dhis2_version': 'dev',
    'java_major': '17',
    'latest_major': False,
    'latest_overall': False,
})

# Send list to stdout as JSON
print(json.dumps(full_matrix))
