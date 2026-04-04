import socket
import time

UDP_IP = "192.168.240.255"
UDP_PORT = 10025

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

for i in range(1):
    sock.sendto(b"A", (UDP_IP, UDP_PORT))
    print(f"Sent A ({i + 1}/10)")
    time.sleep(0.05)

sock.close()
