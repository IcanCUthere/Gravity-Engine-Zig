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
layout (location = 1) in vec3 inNormal;
layout (location = 2) in vec2 inTexCoords;

layout(location = 0) out vec3 outNormal;
layout(location = 1) out vec3 outPos;

layout(location = 2) out vec2 outTexCoords;
layout(location = 3) out vec3 outLightPos;

layout(location = 4) out vec3 outViewPos;

void main() {
    outPos = vec3(Model.transform * vec4(inPosition, 1.0));  
    outNormal = mat3(transpose(inverse(Model.transform))) * inNormal;
    
    outTexCoords = inTexCoords;
    outLightPos = vec3(0.0, 0.0, -10.0);
    outViewPos = Camera.position;

    gl_Position = Camera.projection * Camera.transform * vec4(outPos, 1.0);
}