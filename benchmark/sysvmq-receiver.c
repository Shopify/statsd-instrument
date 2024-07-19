 #include <errno.h>
 #include <stdio.h>
 #include <stdlib.h>
 #include <sys/ipc.h>
 #include <sys/msg.h>
 #include <time.h>
 #include <unistd.h>

 struct msgbuf {
     long mtype;
     char mtext[1024 * 1024];
 };

 int
 main(int argc, char *argv[])
 {
     int  qid;
     int  msgtype = 1;

     qid = msgget(0xDEADBEEF, IPC_CREAT | 0777);

     if (qid == -1) {
         perror("msgget");
         exit(EXIT_FAILURE);
     }

     struct msgbuf msg;
     while (1) {
        msgrcv(qid, &msg, sizeof(msg.mtext), msgtype, MSG_NOERROR);
     }
 }
