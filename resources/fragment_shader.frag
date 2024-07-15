#version 460 
#extension GL_ARB_separate_shader_objects : enable 
#extension GL_ARB_shading_language_420pack : enable 

layout(location = 0) in vec3 inNormal;
layout(location = 1) in vec3 inPos;
layout(location = 2) in vec2 inTexCoords;
layout(location = 3) in vec3 inLightPos;

layout (set = 1, binding = 0) uniform sampler2D texSampler;

layout (location = 0) out vec4 outFragColor; 

//void main() { 
//    outFragColor = texture(texSampler, inTexCoords);
//}  

void main() { 
    
    vec3 lightColor = vec3(1.0, 1.0, 1.0);
    
    //ambient
    float ambientStrength = 0.1;
    vec3 ambient = ambientStrength * lightColor;

    //diffuse
    vec3 norm = normalize(inNormal);
    vec3 lightDir = normalize(inLightPos - inPos);  
    float diffStrength = max(-dot(norm, lightDir), 0.0);
    vec3 diffuse = diffStrength * lightColor;

    //specular
    float specularStrength = 0.7;
    vec3 viewDir = normalize(-inPos); // the viewer is always at (0,0,0) in view-space, so viewDir is (0,0,0) - Position => -Position
    vec3 reflectDir = reflect(-lightDir, norm);  
    float spec = pow(max(-dot(viewDir, reflectDir), 0.0), 32);
    vec3 specular = specularStrength * spec * lightColor; 

    outFragColor = vec4((ambient + diffuse + specular), 1.0) * texture(texSampler, inTexCoords);
}  