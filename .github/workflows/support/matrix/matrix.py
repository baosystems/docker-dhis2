import json
from packaging.version import Version
import urllib3

########

# Initialization

# Default version of Java to use with builds unless specified
default_jdk = 11

# Default version of Java to use with builds v41 or higher
default_jdk_41up = 17

# Initialize the full matrix dict
full_matrix={
    'dhis2_version': [],
    'java_major': [str(default_jdk)],
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

    major_details = [i for i in stable_json['versions'] if i['name'] == dhis2_major][0]

    major_jdk = major_details.get('jdk', default_jdk)

    # List of all patch versions within a major release version
    patch_versions = major_details['patchVersions']

    # Add the "name" value at the full version
    for patch_version in patch_versions:
        dhis2_major_versions.append(patch_version['name'])

    # Remove duplicate entries from the list
    dhis2_major_versions_distinct = list(set(dhis2_major_versions))

    # Sort the list by semantic version
    dhis2_major_versions_sorted = sorted(dhis2_major_versions_distinct, key=lambda x: Version(x))

    # Add unique and sorted list to dhis2_versions dict
    dhis2_versions[dhis2_major] = dhis2_major_versions_sorted

    # Add dev version to list of builds; versions v41 and up may require a newer version Java
    if Version(dhis2_major) < Version('41'):
        full_matrix['dhis2_version'].append(f"{dhis2_major}-dev")
    else:
        full_matrix['include'].append({
            'dhis2_version': f"{dhis2_major}-dev",
            'java_major': major_jdk,
            'latest_major': False,
            'latest_overall': False,
        })

    # Loop each release version, from oldest to newest
    for version in dhis2_major_versions_sorted:

        # Start item with the same properties as the default builds
        matrix_item = {
            'dhis2_version': version,
            'java_major': str(default_jdk),
            'latest_major': False,
            'latest_overall': False,
        }

        # Use the specified version of Java if greater than the default
        if major_jdk > default_jdk:
            matrix_item['java_major'] = str(major_jdk)

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

            if matrix_item['java_major'] == str(default_jdk):
                # Add the release to the list of default builds
                full_matrix['dhis2_version'].append(version)

            else:
                # Add newer Java release to the list of non-default builds
                full_matrix['include'].append(matrix_item)

# If dhis.war exists in releases.dhis2.org, include the dev release for the next major version
dhis2_major_next = f"{Version(dhis2_majors_sorted[-1]).major}.{Version(dhis2_majors_sorted[-1]).minor+1}"
dhis2_major_next_war_resp = http.request('HEAD', f'https://releases.dhis2.org/{dhis2_major_next}/dhis.war')
if dhis2_major_next_war_resp.status == 200:
    full_matrix['include'].append({
        'dhis2_version': f"{dhis2_major_next}-dev",
        'java_major': default_jdk_41up,
        'latest_major': False,
        'latest_overall': False,
    })

# Include a build for "dev"
full_matrix['include'].append({
    'dhis2_version': 'dev',
    'java_major': default_jdk_41up,
    'latest_major': False,
    'latest_overall': False,
})

# Send list to stdout as JSON
print(json.dumps(full_matrix))
