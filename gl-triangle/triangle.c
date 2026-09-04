#include <GL/freeglut.h>

#include <stdio.h>

static int reported_frame;

static void display(void) {
    glClearColor(0.035f, 0.045f, 0.075f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    glBegin(GL_TRIANGLES);
    glColor3f(1.0f, 0.18f, 0.16f);
    glVertex2f(-0.72f, -0.58f);
    glColor3f(0.16f, 1.0f, 0.30f);
    glVertex2f(0.72f, -0.58f);
    glColor3f(0.18f, 0.42f, 1.0f);
    glVertex2f(0.0f, 0.72f);
    glEnd();

    glutSwapBuffers();
    glFinish();

    if (!reported_frame) {
        puts("gl-triangle: rendered frame successfully");
        fflush(stdout);
        reported_frame = 1;
    }
}

static void reshape(int width, int height) {
    glViewport(0, 0, width, height);
}

int main(int argc, char **argv) {
    const GLubyte *vendor;
    const GLubyte *renderer;
    const GLubyte *version;

    glutInit(&argc, argv);
    glutInitDisplayMode(GLUT_DOUBLE | GLUT_RGB);
    glutInitWindowSize(800, 600);
    glutCreateWindow("Vinix OpenGL Triangle");

    vendor = glGetString(GL_VENDOR);
    renderer = glGetString(GL_RENDERER);
    version = glGetString(GL_VERSION);
    printf("gl-triangle: GL_VENDOR=%s\n", vendor ? (const char *)vendor : "unknown");
    printf("gl-triangle: GL_RENDERER=%s\n", renderer ? (const char *)renderer : "unknown");
    printf("gl-triangle: GL_VERSION=%s\n", version ? (const char *)version : "unknown");
    fflush(stdout);

    glutDisplayFunc(display);
    glutReshapeFunc(reshape);
    glutMainLoop();
    return 0;
}
