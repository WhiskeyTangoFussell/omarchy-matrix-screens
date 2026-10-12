#version 440

// Matrix Screens cell renderer (from omatrix). The whole screen is one quad; every fragment works
// out which terminal cell it is in, reads that cell's state (glyph index,
// palette slot, bold flag) from a tiny COLS x LINES texture and samples the
// matching glyph from a pre-rendered font atlas. The CPU only ever touches
// the cells that changed, exactly like ncurses updating a terminal.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;        // quad size in item pixels
    vec2 cellSize;        // terminal cell size in the same units
    vec2 gridSize;        // COLS, LINES
    vec2 atlasSize;       // atlas canvas size in item pixels
    float atlasColumns;   // glyph slots per atlas row
    float atlasRows;      // rows per weight (regular, then bold below)
    float glyphCount;     // number of valid glyph indices
    float columnStride;   // distance between the left edges of drawn (even) columns
    mat4 paletteA;        // palette slots 0..3, one color per column
    mat4 paletteB;        // palette slots 4..7
    mat4 paletteC;        // palette slots 8..11 (tail colors)
    mat4 paletteD;        // palette slots 12..15
    mat4 paletteE;        // palette slots 16..19
    float tailCount;      // tail colors in use (slots 8 .. 8 + tailCount - 1)
};

layout(binding = 1) uniform sampler2D stateTex;
layout(binding = 2) uniform sampler2D atlasTex;

vec4 paletteColor(int slot) {
    if (slot < 4) return paletteA[slot];
    if (slot < 8) return paletteB[slot - 4];
    if (slot < 12) return paletteC[slot - 8];
    if (slot < 16) return paletteD[slot - 12];
    return paletteE[min(slot, 19) - 16];
}

void main() {
    vec2 px = qt_TexCoord0 * itemSize;
    vec2 cell = floor(px / cellSize);

    // cmatrix only draws even columns. Place them every columnStride pixels
    // (2 cells for a terminal grid, wider when justified to the screen
    // edges); anything between a column's glyph and the next is empty.
    float column = floor(px.x / columnStride);
    if (px.x - column * columnStride >= cellSize.x) {
        fragColor = vec4(0.0);
        return;
    }
    cell.x = column * 2.0;

    if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= gridSize.x || cell.y >= gridSize.y) {
        fragColor = vec4(0.0);
        return;
    }

    // Each cell is a square of texels whose size depends on the window's
    // device pixel ratio. Measure it from the image width and fetch the
    // square's center texel by index: the edges are antialiased, and the
    // image can come out a row larger than the grid at a fractional scale,
    // which a normalized lookup would drift into (the bottom row never showed).
    float texelsPerCell = float(textureSize(stateTex, 0).x) / gridSize.x;
    vec4 state = texelFetch(stateTex, ivec2(floor((cell + 0.5) * texelsPerCell)), 0);
    // Painted cells are opaque; a transparent texel is canvas the grid never
    // covered (fractional scaling rounds the backing image up a row), which
    // would otherwise decode as glyph 0, a row of white '!'.
    if (state.a < 0.5) {
        fragColor = vec4(0.0);
        return;
    }
    float glyph = floor(state.r * 255.0 + 0.5);
    if (glyph >= glyphCount) {
        fragColor = vec4(0.0);
        return;
    }

    // Green byte: bits 0..4 palette slot, bits 5..7 a blend toward the next
    // tail color in eighths (tail hue sweep).
    float colorByte = floor(state.g * 255.0 + 0.5);
    int slot = int(mod(colorByte, 32.0));
    float blend = floor(colorByte / 32.0) / 8.0;
    // Blue byte: bit 0 bold, bits 1..5 tail fade level (0 = full color,
    // 31 = dimmest), so a fading tail blends toward the layer behind it.
    float flags = floor(state.b * 255.0 + 0.5);
    float bold = mod(flags, 2.0);
    float brightness = 1.0 - floor(flags / 2.0) / 31.0;

    float atlasRow = floor(glyph / atlasColumns);
    float atlasCol = glyph - atlasRow * atlasColumns;
    atlasRow += bold * atlasRows;

    vec2 local = vec2(px.x - column * columnStride, px.y - cell.y * cellSize.y);
    vec2 atlasPx = vec2(atlasCol, atlasRow) * cellSize + local;
    float coverage = texture(atlasTex, atlasPx / atlasSize).a;

    vec4 color = paletteColor(slot);
    if (blend > 0.0 && slot >= 8) {
        int next = 8 + int(mod(float(slot - 8 + 1), max(tailCount, 1.0)));
        color = mix(color, paletteColor(next), blend);
    }
    float alpha = color.a * coverage * brightness * qt_Opacity;
    fragColor = vec4(color.rgb * alpha, alpha);
}
