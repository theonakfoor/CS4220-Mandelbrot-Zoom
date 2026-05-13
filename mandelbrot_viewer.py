import io
import socket
import threading
import queue
import sys

import pygame

from PIL import Image

sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
sock.bind(('::1', 9999, 0, 0))
sock.listen()

frame_queue = queue.Queue(maxsize=2)

def recv_n(conn, n):
	data = b""
	while len(data) < n:
		chunk = conn.recv(n - len(data))
		if not chunk:
			print("Connection closed")
			sys.exit(0)
		data += chunk
	return data

def receiver(conn):
	"""Background thread worker to recv frames quickly."""
	while True:
		frame_size = recv_n(conn, 4)
		frame_size = int.from_bytes(frame_size, byteorder='big')
  
		frame_data = recv_n(conn, frame_size)

		if frame_queue.full():
			try:
				frame_queue.get_nowait()
			except queue.Empty:
				pass
		
		frame_queue.put(frame_data)
		print("RECEIVED FRAME DATA")

def render(conn):
	thr = threading.Thread(target=receiver, args=(conn,), daemon=True)
	thr.start()

	pygame.init()
	screen = None

	while True:
		for event in pygame.event.get():
			if event.type == pygame.QUIT:
				pygame.quit()
				exit()

		try:
			frame_data = frame_queue.get(timeout=5)			
			img = Image.open(io.BytesIO(frame_data))		
	
			if screen is None:
				screen = pygame.display.set_mode((img.width, img.height))
				pygame.display.set_caption("Mandelbrot Zoom Render")

			surface = pygame.image.fromstring(img.tobytes(), img.size, img.mode)
			screen.blit(surface, (0, 0))
			pygame.display.flip()		
		except queue.Empty:
			pass
		except Exception as e:
			print(f"FAILURE {str(e)}")
			sys.exit(1)

conn, addr = sock.accept()
render(conn)
