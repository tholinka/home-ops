#!/usr/bin/python

# mostly from https://stackoverflow.com/questions/22624653/create-a-virtual-serial-port-connection-over-tcp/64394570#64394570


import logging
from systemd.journal import JournalHandler

log = logging.getLogger('serial-forward')
log.addHandler(JournalHandler())
log.setLevel(logging.INFO)

import argparse

parser = argparse.ArgumentParser("Serial Forward", "Forward serial device to TCP")
parser.add_argument("-d", "--device", help="Serial device to forward, e.g. /dev/ttyAMA0", type=str, default="/dev/ttyAMA0")
parser.add_argument("-p", "--port", help="TCP port to wait for a connection on", type=int, default="6638")
parser.add_argument("-a", "--address", help="IP address to listen on, set to blank for all", type=str, default="")

args = parser.parse_args()

import socket
import sys
import serial

log.info("Opening device: %s", args.device);
ser = serial.Serial(args.device, 115200, timeout=0)

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)

server_address = (args.address, args.port)
log.info('starting up on "%s" port %s', *server_address)
sock.bind(server_address)

sock.listen(1)

while True:
    log.info('waiting for a connection')
    connection, client_address = sock.accept()
    try:
        log.info('connection from: %s', client_address)

        #continously send from serial port to tcp and viceversa
        connection.settimeout(0.1)
        while True:
            try:
                data = connection.recv(16)
                if data == '': break
                ser.write(data)
            except KeyboardInterrupt:
                connection.close()
                sys.exit()
            except Exception as e:
                pass
            received_data = ser.read(ser.inWaiting())
            connection.sendall(received_data)
    except Exception as e:
        log.exception("Exception")

    finally:
        connection.close()
