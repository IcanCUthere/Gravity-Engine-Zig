#version 450
#extension GL_ARB_separate_shader_objects : enable 
#extension GL_ARB_shading_language_420pack : enable 

layout (std140, binding = 0) uniform matrices {
    mat4 model;
    mat4 view;
    mat4 projection;
} Matrices;

layout (location = 0) in vec3 inPosition;
layout (location = 1) in vec3 inNormal;

layout(location = 0) out vec3 outFragColor;
layout(location = 1) out vec3 outNormal;
layout(location = 2) out vec3 outPos;

void main() {
    gl_Position = Matrices.projection * Matrices.view * Matrices.model * vec4(inPosition, 1.0);
    outFragColor = vec3(0.6, 0.8, 0.4);
    outNormal = vec3(Matrices.model * vec4(inNormal, 1.0));
    outPos = vec3(Matrices.model * vec4(inPosition, 1.0));
}