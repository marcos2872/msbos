# MyOS — NVIDIA: força o vendor GLX da NVIDIA.
#
# Em setups híbridos (iGPU + dGPU), aplicativos Wayland/GL passam a renderizar
# na dGPU. Para rodar um app NA iGPU: __GLX_VENDOR_LIBRARY_NAME=mesa <app>
export __GLX_VENDOR_LIBRARY_NAME=nvidia
