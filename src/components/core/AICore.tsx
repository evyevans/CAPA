import React, { useRef, useEffect } from 'react';
import { Canvas, useFrame, extend, Object3DNode } from '@react-three/fiber';
import * as THREE from 'three';
import { BlobShaderMaterial } from './BlobShaderMaterial';

extend({ BlobShaderMaterial });

declare module '@react-three/fiber' {
  interface ThreeElements {
    blobShaderMaterial: Object3DNode<THREE.ShaderMaterial, typeof BlobShaderMaterial> & {
      uColor?: THREE.Color;
      uTime?: number;
      uSpeed?: number;
      uNoiseDensity?: number;
      uNoiseStrength?: number;
      transparent?: boolean;
    };
  }
}

interface CoreMeshProps {
  isSpeakingRef: React.MutableRefObject<boolean>;
}

const CoreMesh = ({ isSpeakingRef }: CoreMeshProps) => {
  const materialRef = useRef<THREE.ShaderMaterial & {
    uTime: number;
    uSpeed: number;
    uNoiseDensity: number;
    uNoiseStrength: number;
  }>(null);
  const groupRef = useRef<THREE.Group>(null);
  // For manual smooth orbit rotation – avoids re-mounting OrbitControls
  const rotationRef = useRef({ y: 0 });

  useFrame((state) => {
    const speaking = isSpeakingRef.current;

    if (materialRef.current) {
      materialRef.current.uTime = state.clock.elapsedTime;
      materialRef.current.uSpeed = THREE.MathUtils.lerp(
        materialRef.current.uSpeed || 0.3,
        speaking ? 1.0 : 0.3,
        0.04
      );
      materialRef.current.uNoiseStrength = THREE.MathUtils.lerp(
        materialRef.current.uNoiseStrength || 0.15,
        speaking ? 0.4 : 0.15,
        0.04
      );
    }

    if (groupRef.current) {
      const t = state.clock.elapsedTime;
      const floatSpeed = speaking ? 4 : 2;
      const tiltSpeed = speaking ? 1.5 : 0.5;
      groupRef.current.position.y = Math.sin(t * floatSpeed) * 0.08;
      groupRef.current.rotation.x = Math.sin(t * tiltSpeed) * 0.08;
      // Continuous Y auto-rotate without prop changes
      rotationRef.current.y += (speaking ? 0.012 : 0.004);
      groupRef.current.rotation.y = rotationRef.current.y;
    }
  });

  return (
    <group ref={groupRef}>
      <mesh>
        <icosahedronGeometry args={[1, 24]} />
        <blobShaderMaterial
          ref={materialRef}
          uColor={new THREE.Color('#EAB308')}
          uSpeed={0.3}
          uNoiseDensity={1.2}
          uNoiseStrength={0.15}
          transparent={true}
        />
      </mesh>

      {/* Outer volumetric corona */}
      <mesh scale={1.22}>
        <icosahedronGeometry args={[1, 12]} />
        <meshBasicMaterial
          color="#FFD700"
          transparent={true}
          opacity={0.12}
          blending={THREE.AdditiveBlending}
          depthWrite={false}
          side={THREE.BackSide}
        />
      </mesh>
    </group>
  );
};

interface AICoreProps {
  isSpeaking?: boolean;
}

export const AICore = React.memo(({ isSpeaking = false }: AICoreProps) => {
  // Pass speaking state via a ref so the Canvas never re-mounts on prop change
  const isSpeakingRef = useRef(isSpeaking);
  useEffect(() => {
    isSpeakingRef.current = isSpeaking;
  }, [isSpeaking]);

  return (
    <div className="w-full h-full relative flex items-center justify-center pointer-events-auto">
      <Canvas
        camera={{ position: [0, 0, 4.5], fov: 45 }}
        gl={{
          antialias: true,
          alpha: true,
          powerPreference: 'high-performance',
          // Prevent context loss on tab switch
          preserveDrawingBuffer: false,
        }}
        // Fixed DPR — no dynamic DPR scaling which causes glitches
        dpr={Math.min(window.devicePixelRatio, 2)}
        frameloop="always"
      >
        <ambientLight intensity={0.6} />
        <CoreMesh isSpeakingRef={isSpeakingRef} />
      </Canvas>
    </div>
  );
});
