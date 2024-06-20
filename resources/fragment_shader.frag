#version 450 
#extension GL_ARB_separate_shader_objects : enable 
#extension GL_ARB_shading_language_420pack : enable 

layout(location = 0) in vec3 inFragColor;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec3 inPos;

layout (location = 0) out vec4 outFragColor; 

void main() { 
    vec3 lightColor = vec3(1.0, 1.0, 1.0);
    float ambientStrength = 0.1;

    vec3 ambient = ambientStrength * lightColor;

    vec3 lightPos = vec3(0.0, 400.0, 0.0);

    vec3 norm = normalize(inNormal);
    vec3 lightDir = normalize(lightPos - inPos);  

    
    float diff = max(dot(norm, lightDir) * 1.0, 0.0);
    vec3 diffuse = diff * lightColor;

    vec3 result = (ambient + diffuse) * inFragColor;

    outFragColor = vec4(result, 1.0);
}  