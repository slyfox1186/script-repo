#!/usr/bin/env bash

set -euo pipefail

# Function to display help menu
show_help() {
    cat << EOF
Usage: ${0##*/} [-h] COMMAND [ARGS...]

Master script for creating and converting security certificates using OpenSSL.

Commands:

  ca_create <name> [days]                 
      Create a Certificate Authority (CA)
      (Generates <name>.key and <name>.crt files)

  ca_sign <ca_name.crt> <ca_key.key> <csr_file.csr> <cert_file.crt> [days]
      Sign a certificate using the CA
      (Requires <ca_name>.crt, <ca_key>.key, and <csr_file>.csr)
      (Generates <cert_file>.crt)

  cert_convert <input_file> <output_file> <input_format> <output_format>
      Convert certificate formats (PEM, DER, PFX)
      (Requires <input_file>.<input_format> to be an existing certificate)
      (Generates <output_file>.<output_format>)

  cert_revoke <ca_name.crt> <ca_key.key> <cert_file.crt>       
      Revoke a certificate
      (Requires <ca_name>.crt, <ca_key>.key, and <cert_file>.crt)

  cert_verify <cert_file.crt>                 
      Verify a certificate
      (Requires <cert_file>.crt to be an existing certificate)

  csr_gen                                 
      Generate a Certificate Signing Request (CSR)
      (Requires an existing key file)

  key_ecc <key_file.key> [curve_name]             
      Generate an ECC private key
      (Generates <key_file>.key)
      (Optional: specify curve_name, default is prime256v1)
      (Common curve names: prime256v1, secp384r1, secp521r1)

  key_rsa <key_file.key>                          
      Generate an RSA private key
      (Prompts for key size: 1024, 2048, 4096; generates <key_file>.key)

  self_sign <csr_file.csr> <key_file.key> <cert_file.crt> [days]
      Generate a self-signed certificate
      (Requires <csr_file>.csr and <key_file>.key)

  ca_crl <ca_name.crt> <ca_key.key> <crl_file.crl> [days]
      Generate a Certificate Revocation List (CRL)
      (Requires <ca_name>.crt and <ca_key>.key)
      (Generates <crl_file>.crl)

Options:

  -h                                      
      Display this help and exit

Examples:

  ${0##*/} key_rsa mykey.key
  ${0##*/} key_ecc mykey.key prime256v1
  ${0##*/} csr_gen
  ${0##*/} self_sign mycsr.csr mykey.key mycert.crt 365
  ${0##*/} cert_convert mycert.pem mycert.der pem der
  ${0##*/} ca_create myca 3650
  ${0##*/} ca_sign myca.crt myca.key mycsr.csr mycert.crt 365
  ${0##*/} cert_revoke myca.crt myca.key mycert.crt
  ${0##*/} cert_verify mycert.crt
  ${0##*/} ca_crl myca.crt myca.key myca.crl 30
EOF
}

# Function to prompt before overwriting a file
confirm_overwrite() {
    local file=$1
    if [[ -f "${file}" ]]; then
        read -p "File ${file} already exists. Overwrite? (y/n): " choice
        case "$choice" in 
            y|Y ) echo "Overwriting ${file}.";;
            n|N ) echo "Operation cancelled."; exit 1;;
            * ) echo "Invalid choice. Operation cancelled."; exit 1;;
        esac
    fi
}

# Create a Certificate Authority (CA)
ca_create() {
    local ca_name=$1
    local days=${2:-3650}
    local ca_key="${ca_name}.key"
    local ca_cert="${ca_name}.crt"

    confirm_overwrite "${ca_key}"
    confirm_overwrite "${ca_cert}"

    openssl genpkey -algorithm RSA -out "${ca_key}" -pkeyopt rsa_keygen_bits:4096
    openssl req -x509 -new -nodes -key "${ca_key}" -sha256 -days "${days}" -out "${ca_cert}" -subj "/C=US/ST=CA/O=My CA/CN=My CA"
    echo "Certificate Authority created: ${ca_cert}"
}

# Sign a certificate using the CA
ca_sign() {
    local ca_cert=$1
    local ca_key=$2
    local csr_file=$3
    local cert_file=$4
    local days=${5:-365}

    if [[ ! -f "${csr_file}" ]]; then
        echo "Error: CSR file ${csr_file} does not exist."
        exit 1
    fi

    confirm_overwrite "${cert_file}"

    openssl x509 -req -in "${csr_file}" -CA "${ca_cert}" -CAkey "${ca_key}" -CAcreateserial -out "${cert_file}" -days "${days}" -sha256
    echo "Certificate signed by CA: ${cert_file}"
}

# Convert certificate formats
cert_convert() {
    local input_file=$1
    local output_file=$2
    local input_format=$3
    local output_format=$4

    if [[ ! -f "${input_file}.${input_format}" ]]; then
        echo "Error: Input file ${input_file}.${input_format} does not exist."
        exit 1
    fi

    confirm_overwrite "${output_file}.${output_format}"

    case "${input_format}" in
        pem)
            if [[ "${output_format}" == "der" ]]; then
                openssl x509 -in "${input_file}.pem" -outform DER -out "${output_file}.der"
            elif [[ "${output_format}" == "pfx" ]]; then
                openssl pkcs12 -export -out "${output_file}.pfx" -in "${input_file}.pem" -inkey "${input_file}.key"
            else
                echo "Unsupported conversion: ${input_format} to ${output_format}"
                exit 1
            fi
            ;;
        der)
            if [[ "${output_format}" == "pem" ]]; then
                openssl x509 -in "${input_file}.der" -inform DER -out "${output_file}.pem" -outform PEM
            else
                echo "Unsupported conversion: ${input_format} to ${output_format}"
                exit 1
            fi
            ;;
        pfx)
            if [[ "${output_format}" == "pem" ]]; then
                openssl pkcs12 -in "${input_file}.pfx" -out "${output_file}.pem" -nodes
            else
                echo "Unsupported conversion: ${input_format} to ${output_format}"
                exit 1
            fi
            ;;
        *)
            echo "Unsupported input format: ${input_format}"
            exit 1
            ;;
    esac
    echo "Certificate converted: ${output_file}.${output_format}"
}

# Revoke a certificate
cert_revoke() {
    local ca_cert=$1
    local ca_key=$2
    local cert_file=$3
    local crl_file="${ca_cert%.crt}.crl"

    if [[ ! -f "${cert_file}" ]]; then
        echo "Error: Certificate file ${cert_file} does not exist."
        exit 1
    fi

    openssl ca -revoke "${cert_file}" -keyfile "${ca_key}" -cert "${ca_cert}"
    openssl ca -gencrl -keyfile "${ca_key}" -cert "${ca_cert}" -out "${crl_file}"
    echo "Certificate revoked and CRL updated: ${crl_file}"
}

# Verify a certificate
cert_verify() {
    local cert_file=$1

    if [[ ! -f "${cert_file}" ]]; then
        echo "Error: Certificate file ${cert_file} does not exist."
        exit 1
    fi

    openssl verify "${cert_file}"
}

# Generate Certificate Signing Request (CSR) interactively
csr_gen() {
    read -p "Enter the path to the key file (with extension): " key_file
    read -p "Enter the path for the CSR file to be generated (with extension): " csr_file

    read -p "Country (2 letter code) [C]: " country
    read -p "State or Province Name (full name) [ST]: " state
    read -p "Locality Name (eg, city) [L]: " locality
    read -p "Organization Name (eg, company) [O]: " organization
    read -p "Organizational Unit Name (eg, section) [OU]: " organizational_unit
    read -p "Common Name (e.g. server FQDN or YOUR name) [CN]: " common_name

    subject="/C=${country}/ST=${state}/L=${locality}/O=${organization}/OU=${organizational_unit}/CN=${common_name}"

    if [[ ! -f "${key_file}" ]]; then
        echo "Error: Key file ${key_file} does not exist."
        exit 1
    fi

    confirm_overwrite "${csr_file}"

    openssl req -new -key "${key_file}" -out "${csr_file}" -subj "${subject}"
    echo "CSR generated: ${csr_file}"
}

# Generate ECC private key
key_ecc() {
    local key_file=$1
    local curve_name=${2:-prime256v1}

    confirm_overwrite "${key_file}"

    openssl ecparam -name "${curve_name}" -genkey -noout -out "${key_file}"
    echo "ECC private key (${curve_name}) generated: ${key_file}"
}

# Generate RSA private key
key_rsa() {
    local key_file=$1
    read -p "Enter key size (1024, 2048, 4096): " key_size

    case "${key_size}" in
        1024|2048|4096)
            confirm_overwrite "${key_file}"
            openssl genpkey -algorithm RSA -out "${key_file}" -pkeyopt rsa_keygen_bits:${key_size}
            echo "RSA private key (${key_size} bits) generated: ${key_file}"
            ;;
        *)
            echo "Invalid key size. Please enter 1024, 2048, or 4096."
            exit 1
            ;;
    esac
}

# Generate self-signed certificate
self_sign() {
    local csr_file=$1
    local key_file=$2
    local cert_file=$3
    local days=${4:-365}

    if [[ ! -f "${csr_file}" ]]; then
        echo "Error: CSR file ${csr_file} does not exist."
        exit 1
    fi

    if [[ ! -f "${key_file}" ]]; then
        echo "Error: Key file ${key_file} does not exist."
        exit 1
    fi

    confirm_overwrite "${cert_file}"

    openssl x509 -req -in "${csr_file}" -signkey "${key_file}" -out "${cert_file}" -days "${days}"
    echo "Self-signed certificate generated: ${cert_file}"
}

# Generate Certificate Revocation List (CRL)
ca_crl() {
    local ca_cert=$1
    local ca_key=$2
    local crl_file=$3
    local days=${4:-30}

    confirm_overwrite "${crl_file}"

    openssl ca -gencrl -keyfile "${ca_key}" -cert "${ca_cert}" -out "${crl_file}" -crldays "${days}"
    echo "CRL generated: ${crl_file}"
}

# Main script logic
if [[ $# -lt 1 ]]; then
    show_help
    exit 1
fi

command=$1
shift

case "${command}" in
    ca_create)
        if [[ $# -lt 1 ]]; then
            echo "Usage: ${0##*/} ca_create <name> [days]"
            exit 1
        fi
        ca_create "$@"
        ;;
    ca_sign)
        if [[ $# -lt 4 ]]; then
            echo "Usage: ${0##*/} ca_sign <ca_name.crt> <ca_key.key> <csr_file.csr> <cert_file.crt> [days]"
            exit 1
        fi
        ca_sign "$@"
        ;;
    cert_convert)
        if [[ $# -lt 4 ]]; then
            echo "Usage: ${0##*/} cert_convert <input_file> <output_file> <input_format> <output_format>"
            exit 1
        fi
        cert_convert "$@"
        ;;
    cert_revoke)
        if [[ $# -lt 3 ]]; then
            echo "Usage: ${0##*/} cert_revoke <ca_name.crt> <ca_key.key> <cert_file.crt>"
            exit 1
        fi
        cert_revoke "$@"
        ;;
    cert_verify)
        if [[ $# -lt 1 ]]; then
            echo "Usage: ${0##*/} cert_verify <cert_file.crt>"
            exit 1
        fi
        cert_verify "$@"
        ;;
    csr_gen)
        csr_gen
        ;;
    key_ecc)
        if [[ $# -lt 1 ]]; then
            echo "Usage: ${0##*/} key_ecc <key_file.key> [curve_name]"
            exit 1
        fi
        key_ecc "$@"
        ;;
    key_rsa)
        if [[ $# -lt 1 ]]; then
            echo "Usage: ${0##*/} key_rsa <key_file.key>"
            exit 1
        fi
        key_rsa "$@"
        ;;
    self_sign)
        if [[ $# -lt 3 ]]; then
            echo "Usage: ${0##*/} self_sign <csr_file.csr> <key_file.key> <cert_file.crt> [days]"
            exit 1
        fi
        self_sign "$@"
        ;;
    ca_crl)
        if [[ $# -lt 3 ]]; then
            echo "Usage: ${0##*/} ca_crl <ca_name.crt> <ca_key.key> <crl_file.crl> [days]"
            exit 1
        fi
        ca_crl "$@"
        ;;
    -h|--help)
        show_help
        ;;
    *)
        echo "Unknown command: ${command}"
        show_help
        exit 1
        ;;
esac
