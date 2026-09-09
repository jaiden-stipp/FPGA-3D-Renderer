# OBJ Model Viewer

The model viewer converts a Wavefront OBJ file into persistent FPGA meshes and renders them through Ethernet. It defaults to three instances for small models and one for models that use more than four hardware handles.

## Offline Inspection

Check a model without connecting to the FPGA:

```text
build\software\Release\renderer_model_viewer.exe --inspect software\assets\monkey.obj
```

The report shows the source vertex and triangle counts, normalization values, simplification results, required handle count, and triangles in each handle.

## VGA Use

Program `output_files/Graphics.sof`, set `SW[0]` to ON, and run:

```text
build\software\Release\renderer_model_viewer.exe software\assets\low_poly_crystal.obj 192.168.7.2 4000
```

Use a final frame-count argument for a bounded run:

```text
build\software\Release\renderer_model_viewer.exe software\assets\monkey.obj 192.168.7.2 4000 300 1
```

The optional arguments are `obj-file`, `address`, `port`, `frames`, and `instances`, in that order. A frame count of `0` runs until you exit. An instance count from 1 through 8 overrides the automatic choice.

The viewer does not impose a software frame-rate cap. It submits the next frame as soon as the FPGA confirms that the previous frame reached the VGA display. Actual speed therefore depends on scene cost and Ethernet latency, with the 60 Hz VGA refresh setting the maximum displayed rate.

## Controls

- Arrow keys rotate around X and Y.
- `W`, `A`, `S`, and `D` move the scene vertically and horizontally.
- `Q` and `E` move the scene toward or away from the camera.
- `+` and `-` change its scale.
- Space pauses or resumes automatic rotation.
- `R` resets the view.
- `X` or Escape exits.

## Conversion Pipeline

The parser reads OBJ `v` and `f` records. Face tokens may contain only a vertex index or use the common `vertex/texture/normal` form. Positive and negative OBJ indices are supported. Texture coordinates, normals, materials, groups, and smoothing records are ignored because the FPGA currently uses flat palette colors.

A face with more than three vertices is converted into a triangle fan. The original vertex order is preserved because changing that order reverses the winding and can make backface culling remove visible surfaces.

The loader finds the model's axis-aligned bounds. It subtracts the center of those bounds from every vertex, then applies one uniform scale:

```text
center = (minimum + maximum) / 2
scale = 2 / largest_dimension
normalized_vertex = (source_vertex - center) * scale
```

The largest normalized dimension is therefore 2 units. This keeps imported coordinates near the origin and safely inside the signed Q8.8 range.

Each hardware handle can store 128 unique vertices and 256 triangles. The chunker walks through the triangles and starts a new mesh whenever either limit would be exceeded. Each chunk is uploaded once, and all chunks receive the same model matrix when the complete object is drawn.

If the chunks require more than 16 handles, the loader groups nearby vertices into a 3D grid. Every group is replaced by its average position. Faces that collapse or become duplicates are removed. The grid size rises in small steps until the result fits. The viewer prints the original and reduced geometry counts so this change is never hidden.

During rendering, the computer creates one model matrix per instance from translation, X and Y rotation, and scale. It sends one `DRAW_MESH` command per handle and instance. The FPGA fetches the stored indices and vertices, applies the matrix, and passes each triangle through camera transformation, clipping, projection, backface culling, rasterization, and depth testing. The C++ client waits for the displayed-frame status before starting the next frame.

## Model Requirements

- Export polygon faces with consistent outward winding.
- Use a low-poly model when possible. Simplification preserves the broad shape but removes detail.
- The final result must fit at most 16 chunks.
- Very large triangles can reduce frame rate because rasterization cost depends on covered pixels as well as triangle count.
- OBJ textures and material colors are not used. Triangle colors cycle through palette entries 1 through 16.
