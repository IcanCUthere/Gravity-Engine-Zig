#version 450
#extension GL_ARB_separate_shader_objects : enable 
#extension GL_ARB_shading_language_420pack : enable 

layout (std140, binding = 0) uniform matrices {
    mat4 Matrix;
} Matrices;

layout (location = 0) in vec3 positions;
layout(location = 0) out vec3 fragColor;

vec3 colors[4] = vec3[](
    vec3(1.0, 0.0, 1.0),
    vec3(0.0, 1.0, 1.0),
    vec3(1.0, 0.0, 0.0),
    vec3(1.0, 0.0, 0.0)
);

void main() {
    gl_Position = Matrices.Matrix * vec4(positions, 1.0);
    fragColor = colors[gl_VertexIndex];
}