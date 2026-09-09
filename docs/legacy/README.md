# Legacy RTL

`transform_3d.sv` is the original approximate projection experiment. It is not included in `Graphics.qsf` and is kept only as a reference. The active implementation is `rtl/pipeline/transform_3d_pipeline.sv`.

`vga_clock_div2.sv` is the original fabric clock divider. The active implementation is the Cyclone IV `ALTPLL` wrapper in `rtl/video/vga_pll.sv`.
