// OPTIONAL snippet for the existing CI pipeline. Review and test in a branch first.
// Requires Trivy installed on the CI agent and authenticated access to the image registry.
stage('Scan container image with Trivy') {
    steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail
: "${IMAGE_URI:?Set IMAGE_URI to the immutable image reference or tag produced by CI}"
trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed "$IMAGE_URI"
'''
    }
}
