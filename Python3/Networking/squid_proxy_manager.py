#!/usr/bin/env python3

import paramiko
import argparse
import logging
import sys
import os
from termcolor import colored

class SquidProxyManager:
    def __init__(self, hostname, port, username, password):
        self.hostname = hostname
        self.port = port
        self.username = username
        self.password = password
        self.client = paramiko.SSHClient()
        self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        logging.info(colored("SquidProxyManager initialized with hostname={}, port={}".format(self.hostname, self.port), 'cyan'))

    def connect(self):
        try:
            logging.info(colored("Attempting to connect to {}:{}".format(self.hostname, self.port), 'cyan'))
            self.client.connect(self.hostname, port=self.port, username=self.username, password=self.password)
            logging.info(colored(f"Connected to {self.hostname} on port {self.port}", 'green'))
        except Exception as e:
            logging.error(colored(f"Failed to connect: {e}", 'red'))
            sys.exit(1)

    def disconnect(self):
        self.client.close()
        logging.info(colored("Disconnected from the server", 'green'))

    def execute_command(self, command):
        logging.info(colored("Executing command: {}".format(command), 'cyan'))
        try:
            stdin, stdout, stderr = self.client.exec_command(command)
            stdout.channel.recv_exit_status()
            out = stdout.read().decode()
            err = stderr.read().decode()
            if err:
                logging.error(colored(f"Error executing command '{command}': {err}", 'red'))
            else:
                logging.info(colored(f"Successfully executed command '{command}'", 'green'))
            return out, err
        except Exception as e:
            logging.error(colored(f"Exception during command execution '{command}': {e}", 'red'))
            return "", str(e)

    def check_squid_status(self):
        logging.info(colored("Checking Squid service status", 'cyan'))
        stdout, _ = self.execute_command("systemctl status squid")
        logging.info(colored("Squid Status:", 'cyan'))
        print(colored("\n" + stdout, 'yellow') + "\n")

    def start_squid(self):
        logging.info(colored("Starting Squid service", 'cyan'))
        stdout, _ = self.execute_command("sudo systemctl start squid")
        logging.info(colored("Start Squid Service:", 'cyan'))
        print(colored("\n" + stdout, 'yellow') + "\n")

    def stop_squid(self):
        logging.info(colored("Stopping Squid service", 'cyan'))
        stdout, _ = self.execute_command("sudo systemctl stop squid")
        logging.info(colored("Stop Squid Service:", 'cyan'))
        print(colored("\n" + stdout, 'yellow') + "\n")

    def restart_squid(self):
        logging.info(colored("Restarting Squid service", 'cyan'))
        stdout, _ = self.execute_command("sudo systemctl restart squid")
        logging.info(colored("Restart Squid Service:", 'cyan'))
        print(colored("\n" + stdout, 'yellow') + "\n")

    def view_squid_logs(self):
        logging.info(colored("Viewing Squid logs", 'cyan'))
        stdout, _ = self.execute_command("sudo tail -n 100 /var/log/squid/access.log")
        logging.info(colored("Squid Logs:", 'cyan'))
        print(colored("\n" + stdout, 'yellow') + "\n")

    def view_squid_config(self):
        logging.info(colored("Viewing Squid configuration", 'cyan'))
        stdout, _ = self.execute_command("sudo cat /etc/squid/squid.conf")
        logging.info(colored("Squid Configuration:", 'cyan'))
        print(colored("\n" + stdout, 'yellow') + "\n")

    def update_squid_config(self, config_data):
        logging.info(colored("Updating Squid configuration", 'cyan'))
        try:
            sftp = self.client.open_sftp()
            with sftp.open('/etc/squid/squid.conf', 'w') as config_file:
                config_file.write(config_data)
            sftp.close()
            logging.info(colored("Updated Squid Configuration", 'green'))
        except Exception as e:
            logging.error(colored(f"Failed to update Squid configuration: {e}", 'red'))

    def reload_squid(self):
        logging.info(colored("Reloading Squid service", 'cyan'))
        stdout, _ = self.execute_command("sudo systemctl reload squid")
        logging.info(colored("Reload Squid Service:", 'cyan'))
        print(colored("\n" + stdout, 'yellow') + "\n")

def parse_args():
    parser = argparse.ArgumentParser(description="Squid Proxy Manager")
    parser.add_argument('hostname', help="IP address of the Squid proxy server")
    parser.add_argument('port', type=int, help="Port number for SSH connection")
    parser.add_argument('username', help="SSH username")
    parser.add_argument('password', help="SSH password")
    parser.add_argument('--check-status', action='store_true', help="Check Squid service status")
    parser.add_argument('--start', action='store_true', help="Start Squid service")
    parser.add_argument('--stop', action='store_true', help="Stop Squid service")
    parser.add_argument('--restart', action='store_true', help="Restart Squid service")
    parser.add_argument('--view-logs', action='store_true', help="View Squid logs")
    parser.add_argument('--view-config', action='store_true', help="View Squid configuration")
    parser.add_argument('--update-config', help="Update Squid configuration with provided data")
    parser.add_argument('--reload', action='store_true', help="Reload Squid service")
    return parser.parse_args()

def main():
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
    args = parse_args()
    logging.info(colored("Initializing Squid Proxy Manager script", 'cyan'))

    manager = SquidProxyManager(args.hostname, args.port, args.username, args.password)
    manager.connect()

    try:
        if args.check_status:
            manager.check_squid_status()
        if args.start:
            manager.start_squid()
        if args.stop:
            manager.stop_squid()
        if args.restart:
            manager.restart_squid()
        if args.view_logs:
            manager.view_squid_logs()
        if args.view_config:
            manager.view_squid_config()
        if args.update_config:
            if not args.update_config.endswith('.conf'):
                logging.error(colored("The provided file must have a .conf extension", 'red'))
            elif not os.path.isfile(args.update_config):
                logging.error(colored(f"Configuration file {args.update_config} not found", 'red'))
            else:
                try:
                    with open(args.update_config, 'r') as config_file:
                        config_data = config_file.read()
                    manager.update_squid_config(config_data)
                except Exception as e:
                    logging.error(colored(f"Error reading configuration file {args.update_config}: {e}", 'red'))
        if args.reload:
            manager.reload_squid()
    finally:
        manager.disconnect()
        logging.info(colored("Squid Proxy Manager operations completed", 'green'))

if __name__ == "__main__":
    main()
