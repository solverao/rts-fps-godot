shader_type spatial;

uniform float amplitude : hint_range(0.0, 10.0) = 1.0;
uniform float frequency : hint_range(0.0, 10.0) = 1.0;
uniform float speed : hint_range(0.0, 10.0) = 1.0;
uniform sampler2D wave_noise;

// Función que calcula la altura de las olas
float calculate_wave_height(vec3 world_pos, float time) {
    vec2 uv = world_pos.xz * frequency;
    float wave = sin(uv.x + time * speed) * cos(uv.y + time * speed * 0.5);
    wave += texture(wave_noise, uv * 0.1 + time * 0.05).r * 0.5;
    return wave * amplitude;
}

void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float height = calculate_wave_height(world_pos, TIME);
    VERTEX.y += height;
}