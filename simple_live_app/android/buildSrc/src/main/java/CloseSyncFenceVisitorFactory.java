import com.android.build.api.instrumentation.AsmClassVisitorFactory;
import com.android.build.api.instrumentation.ClassContext;
import com.android.build.api.instrumentation.ClassData;
import com.android.build.api.instrumentation.InstrumentationParameters;
import org.objectweb.asm.ClassVisitor;
import org.objectweb.asm.MethodVisitor;
import org.objectweb.asm.Opcodes;

/** Backports flutter/flutter#188313 to the embedding packaged with this app. */
public abstract class CloseSyncFenceVisitorFactory
        implements AsmClassVisitorFactory<InstrumentationParameters.None> {
    @Override
    public boolean isInstrumentable(ClassData data) {
        String name = data.getClassName();
        return name.equals("io.flutter.embedding.engine.renderer.FlutterRenderer$ImageReaderSurfaceProducer")
                || name.equals("io.flutter.embedding.engine.renderer.FlutterRenderer$ImageTextureRegistryEntry");
    }

    @Override
    public ClassVisitor createClassVisitor(ClassContext context, ClassVisitor next) {
        return new ClassVisitor(Opcodes.ASM9, next) {
            private int patchedMethods;

            @Override
            public MethodVisitor visitMethod(int access, String name, String descriptor,
                    String signature, String[] exceptions) {
                MethodVisitor output = super.visitMethod(access, name, descriptor, signature, exceptions);
                if (!name.equals("waitOnFence") || !descriptor.equals("(Landroid/media/Image;)V")) {
                    return output;
                }
                patchedMethods++;
                // Drop only this method's body. The helper contains the upstream
                // try-with-resources implementation, including exceptional cleanup.
                return new MethodVisitor(Opcodes.ASM9) {
                    @Override
                    public void visitEnd() {
                        output.visitCode();
                        output.visitVarInsn(Opcodes.ALOAD, 1);
                        output.visitMethodInsn(Opcodes.INVOKESTATIC,
                                "com/xycz/simple_live/SyncFenceFix", "waitOnFence",
                                "(Landroid/media/Image;)V", false);
                        output.visitInsn(Opcodes.RETURN);
                        output.visitMaxs(1, 2);
                        output.visitEnd();
                    }
                };
            }

            @Override
            public void visitEnd() {
                if (patchedMethods != 1) {
                    throw new IllegalStateException("Flutter fence API changed; review or remove "
                            + "CloseSyncFenceVisitorFactory before upgrading the embedding.");
                }
                super.visitEnd();
            }
        };
    }
}
