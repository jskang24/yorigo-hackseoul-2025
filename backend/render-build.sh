#!/bin/bash
# Render build script

echo "Installing system dependencies..."
apt-get update
apt-get install -y ffmpeg libavcodec-dev libavformat-dev libavdevice-dev libavutil-dev libavfilter-dev libswscale-dev libswresample-dev

echo "Installing Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

echo "Build complete!"

