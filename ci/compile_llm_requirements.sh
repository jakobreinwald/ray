#!/bin/bash

set -euo pipefail

PYTHON_CODE="$(python -c "import sys; v=sys.version_info; print(f'py{v.major}{v.minor}')")"

for CUDA_CODE in cpu cu121 cu124 ; do
	PYTHON_CUDA_CODE="${PYTHON_CODE}_${CUDA_CODE}"

	echo "--- Compile dependencies for ${PYTHON_CODE}_${CUDA_CODE}"

	UV_COMPILE=(
		uv pip compile
		--generate-hashes
		--strip-extras
		--unsafe-package ray
		--unsafe-package grpcio-tools
		--unsafe-package setuptools
		--index-url "https://pypi.org/simple"
		--extra-index-url "https://download.pytorch.org/whl/${CUDA_CODE}"
		--find-links "https://data.pyg.org/whl/torch-2.3.0+${CUDA_CODE}.html"
		--index-strategy unsafe-best-match
	)

	mkdir -p /tmp/ray-deps

	# Remove the GPU constraints
	cp python/requirements_compiled.txt /tmp/ray-deps/requirements_compiled.txt
	sed -i '/^--extra-index-url /d' /tmp/ray-deps/requirements_compiled.txt
	sed -i '/^--find-links /d' /tmp/ray-deps/requirements_compiled.txt

	# First, extract base test dependencies from the current compiled mono repo one.
	# This also expands to the indirect dependencies for this Python version & platform.
	#
	# Needs to use the exact torch version.
	echo "--- Compile ray base test dependencies"
	"${UV_COMPILE[@]}" \
		-c "/tmp/ray-deps/requirements_compiled.txt" \
		"python/requirements.txt" \
		"python/requirements/cloud-requirements.txt" \
		"python/requirements/base-test-requirements.txt" \
		-o "python/requirements_compiled_ray_test_${PYTHON_CUDA_CODE}.txt"

	# Second, expand it into LLM test dependencies
	echo "--- Compile LLM test dependencies"
	"${UV_COMPILE[@]}" \
		-c "python/requirements_compiled_ray_test_${PYTHON_CUDA_CODE}.txt" \
		"python/requirements.txt" \
		"python/requirements/cloud-requirements.txt" \
		"python/requirements/base-test-requirements.txt" \
		"python/requirements/llm/llm-requirements.txt" \
		"python/requirements/llm/llm-test-requirements.txt" \
		-o "python/requirements_compiled_rayllm_test_${PYTHON_CUDA_CODE}.txt"

	# Third, extract the ray base dependencies from ray base test dependencies.
	# TODO(aslonnie): This should be used for installing ray in the container images.
	echo "--- Compile ray base test dependencies"
	"${UV_COMPILE[@]}" \
		-c "python/requirements_compiled_ray_test_${PYTHON_CUDA_CODE}.txt" \
		"python/requirements.txt" \
		-o "python/requirements_compiled_ray_${PYTHON_CUDA_CODE}.txt"

	# Finally, extract the LLM dependencies from the LLM test dependencies,
	# which is also an expansion of the ray base dependencies.
	# TODO(aslonnie): This should be used for installing ray[llm] in the container images.
	echo "--- Compile LLM dependencies"
	"${UV_COMPILE[@]}" \
		-c "python/requirements_compiled_rayllm_test_${PYTHON_CUDA_CODE}.txt" \
		"python/requirements.txt" \
		"python/requirements/llm/llm-requirements.txt" \
		-o "python/requirements_compiled_rayllm_${PYTHON_CUDA_CODE}.txt"

done
