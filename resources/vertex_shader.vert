#version 460
#extension GL_ARB_separate_shader_objects : enable 
#extension GL_ARB_shading_language_420pack : enable 

layout (set = 0, binding = 0) uniform modelMatrices {
    mat4 transform;
} Model;

layout (set = 1, binding = 0) uniform cameraMatrices {
    mat4 transform;
    mat4 projection;
} Camera;

layout (location = 0) in vec3 inPosition;
layout (location = 1) in vec3 inNormal;
layout (location = 2) in vec2 inTexCoords;

layout(location = 0) out vec3 outNormal;
layout(location = 1) out vec3 outPos;
layout(location = 2) out vec2 outTexCoords;
layout(location = 3) out vec3 outLightPos;

void main() {
    gl_Position = Camera.projection * Camera.transform * Model.transform * vec4(inPosition, 1.0);
    outNormal = mat3(transpose(inverse(Camera.transform * Model.transform))) * inNormal;
    outPos = vec3(Camera.transform * Model.transform * vec4(inPosition, 1.0));  
    outTexCoords = inTexCoords;
    outLightPos = vec3(Camera.transform * vec4(0.0, 0.0, -400.0, 1.0));
}