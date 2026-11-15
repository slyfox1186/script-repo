#!/usr/bin/env bash

set -euo pipefail

CUDA_VERSION=130

while [[ $# -gt 0 ]]; do
	case "$1" in
		-v|--version) CUDA_VERSION="$2"; shift 2 ;;
		*) echo "Unknown option: $1"; exit 1 ;;
	esac
done

runit() {
	echo "[1] stable"
	echo "[2] nightly"
	echo
	read -rp "Your options are [1] or [2]: " answer
	case "$answer" in
	  1)
		VLLM_VERSION=$(curl -fsS https://api.github.com/repos/vllm-project/vllm/releases/latest | grep -oP '"tag_name":\s*"v\K[^"]+')
		uv pip install --system --upgrade --force-reinstall \
		torch torchvision torchaudio \
		"https://github.com/vllm-project/vllm/releases/download/v${VLLM_VERSION}/vllm-${VLLM_VERSION}+cu${CUDA_VERSION}-cp38-abi3-manylinux_2_35_$(uname -m).whl" \
		--extra-index-url "https://download.pytorch.org/whl/cu${CUDA_VERSION}" \
		--index-strategy unsafe-best-match
		;;
	  2)
		uv pip install --system --upgrade vllm \
		--pre --torch-backend=auto \
		--extra-index-url https://wheels.vllm.ai/nightly \
		--index-strategy unsafe-best-match
		;;
	  *)
		printf "\n%s\n" "Invalid choice. Use 1 for nightly or 2 for stable."
		sleep 3
		clear
		runit
		;;
	esac
}
runit
