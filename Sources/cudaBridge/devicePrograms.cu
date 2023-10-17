// ======================================================================== //
// Copyright 2018-2019 Ingo Wald                                            //
//                                                                          //
// Licensed under the Apache License, Version 2.0 (the "License");          //
// you may not use this file except in compliance with the License.         //
// You may obtain a copy of the License at                                  //
//                                                                          //
//     http://www.apache.org/licenses/LICENSE-2.0                           //
//                                                                          //
// Unless required by applicable law or agreed to in writing, software      //
// distributed under the License is distributed on an "AS IS" BASIS,        //
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. //
// See the License for the specific language governing permissions and      //
// limitations under the License.                                           //
// ======================================================================== //

#include <optix_device.h>
#include <cuda_runtime.h>

#include "LaunchParams.h"

using namespace osc;

namespace osc {
  
  /*! launch parameters in constant memory, filled in by optix upon
      optixLaunch (this gets filled in from the buffer we pass to
      optixLaunch) */
  extern "C" __constant__ LaunchParams optixLaunchParams;

  // for this simple example, we have a single ray type
  enum { SURFACE_RAY_TYPE=0, RAY_TYPE_COUNT };
  
  static __forceinline__ __device__
  void *unpackPointer( uint32_t i0, uint32_t i1 )
  {
    const uint64_t uptr = static_cast<uint64_t>( i0 ) << 32 | i1;
    void*           ptr = reinterpret_cast<void*>( uptr ); 
    return ptr;
  }

  static __forceinline__ __device__
  void  packPointer( void* ptr, uint32_t& i0, uint32_t& i1 )
  {
    const uint64_t uptr = reinterpret_cast<uint64_t>( ptr );
    i0 = uptr >> 32;
    i1 = uptr & 0x00000000ffffffff;
  }

  template<typename T>
  static __forceinline__ __device__ T *getPRD()
  { 
    const uint32_t u0 = optixGetPayload_0();
    const uint32_t u1 = optixGetPayload_1();
    return reinterpret_cast<T*>( unpackPointer( u0, u1 ) );
  }
  
  struct PerRayData {
    vec3f intersectionPoint;
    vec3f intersectionNormal;
    int intersected = 0;
    int primID = -1;
  };

  //------------------------------------------------------------------------------
  // closest hit and anyhit programs for radiance-type rays.
  //
  // Note eventually we will have to create one pair of those for each
  // ray type and each geometry type we want to render; but this
  // simple example doesn't use any actual geometries yet, so we only
  // create a single, dummy, set of them (we do have to have at least
  // one group of them to set up the SBT)
  //------------------------------------------------------------------------------
  
  extern "C" __global__ void __closesthit__radiance()
  {
    const TriangleMeshSBTData &sbtData
      = *(const TriangleMeshSBTData*)optixGetSbtDataPointer();
    
    // ------------------------------------------------------------------
    // gather some basic hit information
    // ------------------------------------------------------------------
    const int   primID = optixGetPrimitiveIndex();
    //printf("hit %i\n", primID);
    const vec3i index  = sbtData.index[primID];
    const float u = optixGetTriangleBarycentrics().x;
    const float v = optixGetTriangleBarycentrics().y;

    // ------------------------------------------------------------------
    // compute normal, using either shading normal (if avail), or
    // geometry normal (fallback)
    // ------------------------------------------------------------------
    vec3f N;
    if (sbtData.normal) {
      N = (1.f-u-v) * sbtData.normal[index.x]
        +         u * sbtData.normal[index.y]
        +         v * sbtData.normal[index.z];
    } else {
      const vec3f &A     = sbtData.vertex[index.x];
      const vec3f &B     = sbtData.vertex[index.y];
      const vec3f &C     = sbtData.vertex[index.z];
      N                  = normalize(cross(B-A,C-A));
    }
    N = normalize(N);

    // ------------------------------------------------------------------
    // compute diffuse material color, including diffuse texture, if
    // available
    // ------------------------------------------------------------------
    //vec3f diffuseColor = sbtData.color;
    //if (sbtData.hasTexture && sbtData.texcoord) {
    //  const vec2f tc
    //    = (1.f-u-v) * sbtData.texcoord[index.x]
    //    +         u * sbtData.texcoord[index.y]
    //    +         v * sbtData.texcoord[index.z];
    //  
    //  vec4f fromTexture = tex2D<float4>(sbtData.texture,tc.x,tc.y);
    //  diffuseColor *= (vec3f)fromTexture;
    //}
    //
    // ------------------------------------------------------------------
    // perform some simple "NdotD" shading
    // ------------------------------------------------------------------
    //const vec3f rayDir = optixGetWorldRayDirection();
    //const float cosDN  = 0.2f + .8f*fabsf(dot(rayDir,N));
    //vec3f &prd = *(vec3f*)getPRD<vec3f>();
    //prd = cosDN * diffuseColor;

    //prd = vec3f(0.5);
    //prd = abs(N);
    const vec3f &A     = sbtData.vertex[index.x];
    const vec3f &B     = sbtData.vertex[index.y];
    const vec3f &C     = sbtData.vertex[index.z];
    vec3f P = (1.f-u-v) * A + u * B + v * C;
    //vec3f &prd = *(vec3f*)getPRD<vec3f>();
    PerRayData &prd = *(PerRayData*)getPRD<PerRayData>();
    prd.intersectionPoint = P;
    prd.intersectionNormal = N;
    prd.intersected = 1;
    prd.primID = primID;
    //printf("P: %f %f %f\n", P.x, P.y, P.z);
  }
  
  extern "C" __global__ void __anyhit__radiance()
  { /*! for this simple example, this will remain empty */ }


  
  //------------------------------------------------------------------------------
  // miss program that gets called for any ray that did not have a
  // valid intersection
  //
  // as with the anyhit/closest hit programs, in this example we only
  // need to have _some_ dummy function to set up a valid SBT
  // ------------------------------------------------------------------------------
  
  extern "C" __global__ void __miss__radiance()
  {
    //printf("miss\n");
    //vec3f &prd = *(vec3f*)getPRD<vec3f>();
    PerRayData &prd = *(PerRayData*)getPRD<PerRayData>();
    prd.intersectionPoint = vec3f(1.f);
    prd.intersected = 0;
  }

  //------------------------------------------------------------------------------
  // ray gen program - the actual rendering happens in here
  //------------------------------------------------------------------------------
  extern "C" __global__ void __raygen__renderFrame()
  {
    //printf("render\n");
    // compute a test pattern based on pixel ID
    const int ix = optixGetLaunchIndex().x;
    const int iy = optixGetLaunchIndex().y;

    const auto &camera = optixLaunchParams.camera;

    // our per-ray data for this example. what we initialize it to
    // won't matter, since this value will be overwritten by either
    // the miss or hit program, anyway
    PerRayData perRayData = { vec3f(0.f), vec3f(0.f), false, -1 };

    // the values we store the PRD pointer in:
    uint32_t u0, u1;
    packPointer( &perRayData, u0, u1 );

    // normalized screen plane position, in [0,1]^2
    const vec2f screen(vec2f(ix+.5f,iy+.5f)
                       / vec2f(optixLaunchParams.frame.size));
    
    vec3f rayDir;
    float tmax;
    if (camera.useRay) {
	rayDir = camera.rayDirection;
	tmax = camera.tHit;
    } else {
	rayDir = normalize(camera.direction
                             + (screen.x - 0.5f) * camera.horizontal
                             + (screen.y - 0.5f) * camera.vertical);
	tmax = 1e20f;
    }

    if (ix == 0 && iy == 0) {
	//printf("position %f %f %f\n", camera.position.x, camera.position.y, camera.position.z);
	//printf("rayDir %f %f %f\n", rayDir.x, rayDir.y, rayDir.z);
    }

    vec3f otherRayDir = normalize(camera.direction
                             + (screen.x - 0.5f) * camera.horizontal
                             + (screen.y - 0.5f) * camera.vertical);
    if (ix == 0 && iy == 0) {
	//printf("other %f %f %f\n", otherRayDir.x, otherRayDir.y, otherRayDir.z);
    }
    //rayDir = otherRayDir;

    optixTrace(optixLaunchParams.traversable,
               camera.position,
               rayDir,
               0.f,    // tmin
               tmax,
               0.0f,   // rayTime
               OptixVisibilityMask( 255 ),
               OPTIX_RAY_FLAG_DISABLE_ANYHIT,//OPTIX_RAY_FLAG_NONE,
               SURFACE_RAY_TYPE,             // SBT offset
               RAY_TYPE_COUNT,               // SBT stride
               SURFACE_RAY_TYPE,             // missSBTIndex 
               u0, u1 );

    const int r = int(255.99f*perRayData.intersectionPoint.x);
    const int g = int(255.99f*perRayData.intersectionPoint.y);
    const int b = int(255.99f*perRayData.intersectionPoint.z);

    // convert to 32-bit rgba value (we explicitly set alpha to 0xff
    // to make stb_image_write happy ...
    const uint32_t rgba = 0xff000000
      | (r<<0) | (g<<8) | (b<<16);

    // and write to frame buffer ...
    const uint32_t fbIndex = ix+iy*optixLaunchParams.frame.size.x;
    optixLaunchParams.frame.colorBuffer[fbIndex] = rgba;
    optixLaunchParams.frame.outVertexBuffer[fbIndex] = perRayData.intersectionPoint;
    optixLaunchParams.frame.outNormalBuffer[fbIndex] = perRayData.intersectionNormal;
    optixLaunchParams.frame.intersected[0] = perRayData.intersected;
    optixLaunchParams.frame.primID[0] = perRayData.primID;
  }
} // ::osc
