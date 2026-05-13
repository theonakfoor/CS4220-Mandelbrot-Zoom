CS4220 Final Project
Mandelbrot CPU vs GPU Rendering + Local Python Viewer
Theo Nakfoor

There are two components to this project. 

--- FRAME VIEWING CLIENT (mandelbrot_viewer.py) ---
mandelbrot_view.py is intended to run on your local device to allow you to easily view the generated frames.
The frames are delivered to the client over a TCP connection on port 9999. The client program actually acts as the TCP server
and listens for connection on localhost:9999. The frame rendering engine acts as the client and connects to the client server.
The viewing client needs to be launched first before the rendering engine begins work. As mentioned above, both the rendering engine
and viewing client could be running on the same machine or on different machines. Please see the below instructions on starting the SSH tunnel
if you are runnning on two different machines.

Once the frame rendering engine has connected to the frame viewing client, it will start generating frames either via the CPU or GPU.
Once each frame has been generated, it will send the frame as two individual segments over to the client to be rendered. The first will be 
a header segment including a 4-byte length of the size of the frame (so that the client knows how much to read then render). It will then send a
variable length segment containing the actual frame data. Once received, the frame viewing client will read and render the frame and listen
for the next one.

To run the frame viewing client, your machine will need to have Python 3.11 or greater installed and the following Python
packges installed via "python -m pip install [package name]"
- pygame

Once the required dependencies are installed, run the viewer with the command below:
"python mandelbrot_viewer.py"

This will open the TCP server on port 9999 and begin listening for connections. Follow the below steps to start the rendering engine
which will connect to the viewer and begin sending frames.


--- MANDELBROT FRAME RENDERING ENGINE (mandelbrot.cu) ---
mandelbrot.cu is intended to run on a device with an NVIDIA CUDA enabled GPU installed.
This can be either on a remote computing cluster like NCSA Delta or on your own machine with an NVIDIA GPU installed.

The machine you are running on will need an NVIDIA GPU installed as well as CUDA and nvcc installed.

To run the frame rendering engine, please see below for separate instructions for a local vs remote machine.

On Local Machine:
- To run on local, start by simply compiling the file with "nvcc -o mandelbrot mandelbrot.cu"
- Once compiled, run the file via "./mandelbrot [device/host] [frame width] [frame height]" (NOTE: YOU WILL NEED TO MAKE SURE THE VIEWER IS RUNNING FIRST BEFORE DOING THIS.)
	- Frame width/height will specify the resolution of each Mandelbrot frame being rendered.

On Remote Cluster:
- To run on a remote cluster, start by submitting a batch job for a bash terminal with
"srun --account=bchn-delta-gpu --partition=gpuA40x4-interactive --nodes=1 --gpus-per-node=1 --tasks=1 --tasks-per-node=16 --cpus-per-task=1 --mem=20g --pty bash"
- Compile the file with "nvcc -o mandelbrot mandelbrot.cu"
- Once compiled, run the file via "./mandelbrot [device/host] [frame width] [frame height]" (NOTE: YOU WILL NEED TO MAKE SURE THE VIEWER IS RUNNING FIRST BEFORE DOING THIS.)
	- Frame width/height will specify the resolution of each Mandelbrot frame being rendered.


--- INSTRUCTIONS FOR SSH TUNNELING ---
NOTE: You may skip this step if you are running the rendering engine and viewing client on the same machine.

This project assumes that the rendering engine will be run on a computing cluster like NCSA Delta which blocks incoming TCP connections on arbitrary ports.
In order to circumvent this limitation, we will use an SSH tunnel with a jump. The tunnel will work as follows

Local Computer -> Tunnel (Login Node) -> Jump for Tunnel (Compute Node)

To begin this setup, first create an SSH config file in your /.ssh/config location on your device. Populate it with the below

Host delta
    HostName dt-login02.delta.ncsa.illinois.edu
    User [YOUR USERNAME]
    ForwardX11 yes
    ForwardX11Trusted yes
    Compression yes
    ControlMaster auto
    ControlPersist 2h

Once you've created your SSH config, tunnel with the jump AFTER you've provisioned the batch job where you will run the rendering engine.
Once your job has been allocated resources run the "hostname" command to identify the node you are on. It will be in the format [NODE].delta.ncsa.illinois.edu (Ex: "gpub073.delta.ncsa.illinois.edu")
Use the [NODE] value in the command below to set up the tunnel:

ssh -R 127.0.0.1:9999:localhost:9999 -J delta [YOUR USERNAME]@[NODE]