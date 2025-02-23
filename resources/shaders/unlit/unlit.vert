#version 460
#extension GL_ARB_separate_shader_objects : enable 
#extension GL_ARB_shading_language_420pack : enable 

layout (set = 0, binding = 0) uniform cameraMatrices {
    mat4 transform;
    mat4 projection;
    vec3 position;
} Camera;

layout (set = 2, binding = 0) uniform modelInstanceMatrices {
    mat4 transform;
} Model;

layout (location = 0) in vec3 inPosition;
layout (location = 1) in vec2 inTexCoords;

layout(location = 0) out vec2 outTexCoords;

void main() {
    outTexCoords = inTexCoords;
    gl_Position = Camera.projection * Camera.transform * Model.transform * vec4(inPosition, 1.0);
}