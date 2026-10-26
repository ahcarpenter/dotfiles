// Dims a terminal while it doesn't have focus. Ghostty sets iFocus to 0 for
// every terminal in a window that isn't focused, and for an unfocused split.
const float UNFOCUSED_SATURATION = 0.25;
const float UNFOCUSED_BRIGHTNESS = 0.45;
// Takes the 0.8 background-opacity down to 0.62.
const float UNFOCUSED_OPACITY = 0.775;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec4 color = texture(iChannel0, fragCoord / iResolution.xy);
    if (iFocus == 0) {
        // The color is premultiplied by alpha, so scaling rgb dims the text to
        // 45% while scaling alpha lets more of the blurred desktop through.
        float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
        color.rgb = mix(vec3(luma), color.rgb, UNFOCUSED_SATURATION) * UNFOCUSED_BRIGHTNESS;
        color.a *= UNFOCUSED_OPACITY;
    }
    fragColor = color;
}
