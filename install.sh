#!/bin/sh

sv_print_usage()
{
    echo "Usage: $0 [-h] [install|uninstall]" >&2
}

sv_ask_question()
{
    question="$1"
    default_value="$2"
    variable_name="$3"

    echo -n "$question [$default_value]: " >&2
    read input_value

    [ -z "$input_value" ] && echo "$default_value" || echo "$input_value"
}

sv_install()
{
    cat >&2 <<EOF
This assistant will ask you a handful set of questions to install the service
and its components on this computer.

Default values are shown right besides the question. Press Enter if you want
to accept said default value, or type in the appropriate value if necessary.

EOF

    # ---

    cat >&2 <<EOF
The service requires the use of SSL certificates so that GitHub can contact it
through a webhook. Consequently, this requires an associated domain name for
this task.

We recommend you use certbot to automatically generate keys for your domain
name, and keep them up-to-date.

The path must be a folder containing the following two files:

   - cert.pem, the public key exposed to end users/clients
   - privkey.pem, the private key used to encrypt responses to be decoded by
     end users/clients

EOF
    certificates_path="$(sv_ask_question "Where are the public and private keys located?" \
                                         "/etc/letsencrypt/live/repocrawler.naucto.net")"

    if [ ! -d "$certificates_path" ] || \
       [ ! -f "$certificates_path/cert.pem" ] || \
       [ ! -f "$certificates_path/privkey.pem" ]; then
        echo "$0: Bad certificates path passed, cannot continue."
        exit 1
    fi

    # ---

    cat >&2 <<EOF
The service requires write access to the project owner's student repository.
Thus, we need to have a fine-grained GitHub token associated to a student
account.

Creating a fine-grained GitHub token is easy. Follow the guide on the official
GitHub documentation website:

https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token

Make sure to authenticate your fine-grained GitHub token against the official
Epitech organization associated with your account.

EOF
    github_token="$(sv_ask_question "What is the student GitHub token that you want to use?" "")"

    if [ -z "$github_token" ]; then
        echo "$0: No GitHub token provided, cannot continue."
        exit 1
    fi
}

sv_uninstall()
{
    echo "Not yet implemented"
    exit 1
}

cat <<EOF
Naucto Repository Crawler service installer script
Copyright (C) 2025 Naucto - Under the MIT license. See license.txt for more details.

EOF

if [ "$#" -ne 1 ]; then
    sv_print_usage
    exit 1
fi

primary_command="$1"
shift 1

if [ "$primary_command" = "-h" ]; then
    cat >&2 <<EOF
Utility to setup the Naucto Repository Crawler service on a systemd-based
system.

EOF

    sv_print_usage
   
    cat >&2 <<EOF
Options:

    -h              Show a help message describing the available options

Commands:

    install         Install the Naucto Repository Crawler as a systemd-based
                    service on the current system.

                    This will duplicate the contents of the repository to the
                    installation path, create a systemd service file for it
                    and ask the user a few questions to configure it

    uninstall       Remove the aforementioned service from the system.
EOF

    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "$0: this script requires administrative privileges." >&2
    exit 1
fi

case "$primary_command" in
    install)
        sv_install $@
        exit $?
        ;;

    uninstall)
        sv_uninstall $@
        exit $?
        ;;
esac
