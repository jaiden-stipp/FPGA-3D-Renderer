import socket

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

data = b"hello"

sock.sendto(data, ("192.168.7.2", 4000))

print("sent", len(data), "bytes")