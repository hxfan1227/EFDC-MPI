MODULE DRIFTER
    ! *** DRIFTER.F90 IS A LAGRANGIAN PARTICLE TRACKING MODULE FOR THE DYNAMIC SOLUTIONS VERSION OF EFDC (I.E. EFDC_DS)
    ! *** THIS MODULE COMPLETELY REPLACES THE PREVIOUS VERSIONS OF PARTICLE TRACKING IN EFDC.
    ! *** THE CARDS C67 AND C68 IN THE EFDC.INP FILE WERE LEFT INTACT TO PROVIDE COMPATIBILITY WITH
    ! *** OTHER VERSIONS OF EFDC.

    ! *** January 7th 2019
    ! *** Updated this file to support MPI parallel implementation

    USE GLOBAL

#ifdef key_mpi
    USE MPI
#endif
    IMPLICIT NONE

    LOGICAL(4),PRIVATE::BEDGEMOVE
    REAL(RKD) ,PRIVATE::XLA1,YLA1,ZLA1
    REAL(RKD) ,POINTER,PRIVATE::ZCTR(:)

CONTAINS
  
    SUBROUTINE DRIFTERC   ! ***************************************************************************
        ! SOLVE DIFFERENTIAL EQS. FOR (X,Y,Z):
        ! DX=U.DT+RAN.SQRT(2EH.DT)
        ! DY=V.DT+RAN.SQRT(2EH.DT)
        ! DZ=W.DT+RAN.SQRT(2EV.DT)
        ! U(L,K),V(L,K),W(L,K),K=1,KC,L=2:LA    CURRENT TIME
        ! U1(L,K),V1(L,K),W1(L,K),K=1,KC,L=2:LA PREVIOUS TIME
        ! N: TIME STEP
        INTEGER(4)::NP,VER,COMM_FLAG, ERROR, IL,JL
        REAL(RKD) ::KDX1,KDX2,KDX3,KDX4
        REAL(RKD) ::KDY1,KDY2,KDY3,KDY4
        REAL(RKD) ::KDZ1,KDZ2,KDZ3,KDZ4
        REAL(RKD) ::U1NP,V1NP,W1NP,U2NP,V2NP,W2NP
        CHARACTER*80 TITLE,METHOD
  
        TITLE='PREDICTION OF TRAJECTORIES OF DRIFTERS'
        IF (ISPD==2) THEN
            METHOD='METHOD: EXPLICIT EULER'
        ELSEIF(ISPD==3) THEN
            METHOD='METHOD: PRE-CORRECTOR EULER'
        ELSEIF(ISPD==4) THEN
            METHOD='METHOD: RUNGE-KUTTA 4'
        ENDIF
  
        !----------FIRST CALL--------------------
        IF(JSPD.EQ.1) THEN
            IF (MPI_PAR_FLAG == 1) THEN
                CALL MAP_GLOBAL_LOCAL(0) ! (XLA, YLA, ZLA, XLA_ALL,YLA_ALL,ZLA_ALL)    !OUT:XLA,YLA,LLA,KLA,BELVLA,HPLA
                ! Ensure cell is within local domain & boundary conditions
                DO NP=1,NPD
                    CALL CONTAINER(XLA,YLA,ZLA,LLA,KLA,NP) !OUT:LLA,KLA,BELVLA,HPLA
                ENDDO
            ELSE
                CALL CONTAINER(XLA,YLA,ZLA,LLA,KLA) !OUT:LLA,KLA,BELVLA,HPLA
            ENDIF
            ! *** MAKE SURE THE FILE IS NEW
            OPEN(ULGR,FILE='DRIFTER.OUT',STATUS='UNKNOWN')
            CLOSE(ULGR,STATUS='DELETE')
            OPEN(ULGR,FILE='DRIFTER.OUT',STATUS='UNKNOWN')
            JSPD=0
            VER=101
            WRITE(ULGR,*) VER
            WRITE(ULGR,*) trim(TITLE)
            WRITE(ULGR,*) trim(METHOD)
            WRITE(ULGR,*) NPD_TOT,KC
            WRITE(ULGR,*) TIMEDAY
            WRITE(ULGR,*)(XLA_ALL(NP),YLA_ALL(NP),REAL(ZLA_ALL(NP),4),NP=1,NPD_TOT)
            FLUSH(ULGR)
            TIMENEXT_WRITE_DR=TIMEDAY+LA_FREQ+0.000001
        ENDIF

        !----NEXT CALL---------------------------
        GHOST_ZONE_CHECK=0
        DO NP=1,NPD
            BEDGEMOVE = .FALSE.
            XLA1 = XLA(NP)
            YLA1 = YLA(NP)
            ZLA1 = ZLA(NP)
            IF (ISPD==2) THEN
                !EXPLICIT EULER TO DETERMINE THE NEW POSITION OF DRIFTER:
                IF (LLA(NP)<2.OR.BEDGEMOVE.OR.HPLA(NP)<=0) CYCLE
                CALL DRIFVELCAL(LLA(NP),KLA(NP),NP,U1NP,V1NP,W1NP,U2NP,V2NP,W2NP) !OUT:HOR.VELOCITIES OF DRIFTER NP
                XLA(NP) = XLA1 + DT*U1NP
                YLA(NP) = YLA1 + DT*V1NP
                IF(LA_ZCAL==1) THEN
                    ZLA(NP) = ZLA1 + DT*W1NP
                ELSE
                    ZLA(NP)=HPLA(NP)+BELVLA(NP)-DLA(NP)  !HP interpolation
                ENDIF
                CALL RANDCAL(LLA(NP),KLA(NP),NP)
                CALL CONTAINER(XLA,YLA,ZLA,LLA,KLA,NP) !IT MUST BE HERE

      
            ELSEIF (ISPD==3) THEN
                !EULER PREDICTOR-CORRECTOR
                IF (LLA(NP)<2.OR.BEDGEMOVE.OR.HPLA(NP)<=0) CYCLE
                CALL DRIFVELCAL(LLA(NP),KLA(NP),NP,U1NP,V1NP,W1NP,U2NP,V2NP,W2NP)
                XLA(NP) = XLA1 + DT*U1NP
                YLA(NP) = YLA1 + DT*V1NP
                IF(LA_ZCAL==1) THEN
                    ZLA(NP) = ZLA1 + DT*W1NP
                ELSE
                    ZLA(NP)=HPLA(NP)+BELVLA(NP)-DLA(NP) !HP interpolation
                ENDIF
                CALL CONTAINER(XLA,YLA,ZLA,LLA,KLA,NP)
                IF (LLA(NP)<2.OR.BEDGEMOVE.OR.HPLA(NP)<=0) CYCLE
                CALL DRIFVELCAL(LLA(NP),KLA(NP),NP,KDX1,KDY1,KDZ1,U2NP,V2NP,W2NP)
                XLA(NP) = XLA1 + 0.5*DT*(U1NP+U2NP)
                YLA(NP) = YLA1 + 0.5*DT*(V1NP+V2NP)
                IF(LA_ZCAL==1) THEN
                    ZLA(NP) = ZLA1 + 0.5*DT*(W1NP+W2NP)
                ELSE
                    ZLA(NP)=HPLA(NP)+BELVLA(NP)-DLA(NP)
                ENDIF
                CALL RANDCAL(LLA(NP),KLA(NP),NP)
                CALL CONTAINER(XLA,YLA,ZLA,LLA,KLA,NP)
      
            ELSEIF (ISPD==4) THEN
                !RUNGE-KUTTA 4
                IF (LLA(NP)<2.OR.BEDGEMOVE.OR.HPLA(NP)<=0) CYCLE
                CALL DRIFVELCAL(LLA(NP),KLA(NP),NP,U1NP,V1NP,W1NP,U2NP,V2NP,W2NP)
                KDX1 = DT*U1NP
                KDY1 = DT*V1NP
                KDZ1 = DT*W1NP
                XLA(NP)  = XLA1+0.5*KDX1
                YLA(NP)  = YLA1+0.5*KDY1
                IF(LA_ZCAL==1) THEN
                    ZLA(NP)  = ZLA1+0.5*KDZ1
                ELSE
                    ZLA(NP)=HPLA(NP)+BELVLA(NP)-DLA(NP)
                ENDIF
                CALL CONTAINER(XLA,YLA,ZLA,LLA,KLA,NP)
                IF (LLA(NP)<2.OR.BEDGEMOVE.OR.HPLA(NP)<=0) CYCLE
                CALL DRIFVELCAL(LLA(NP),KLA(NP),NP,U1NP,V1NP,W1NP,U2NP,V2NP,W2NP)
                KDX2 = 0.5*DT*(U1NP+U2NP)
                KDY2 = 0.5*DT*(V1NP+V2NP)
                KDZ2 = 0.5*DT*(W1NP+W2NP)
                XLA(NP)  = XLA1+0.5*KDX2
                YLA(NP)  = YLA1+0.5*KDY2
                IF(LA_ZCAL==1) THEN
                    ZLA(NP)  = ZLA1+0.5*KDZ2
                ELSE
                    ZLA(NP)=HPLA(NP)+BELVLA(NP)-DLA(NP)
                ENDIF
                CALL CONTAINER(XLA,YLA,ZLA,LLA,KLA,NP)
                IF (LLA(NP)<2.OR.BEDGEMOVE.OR.HPLA(NP)<=0) CYCLE
                CALL DRIFVELCAL(LLA(NP),KLA(NP),NP,U1NP,V1NP,W1NP,U2NP,V2NP,W2NP)
                KDX3 = 0.5*DT*(U1NP+U2NP)
                KDY3 = 0.5*DT*(V1NP+V2NP)
                KDZ3 = 0.5*DT*(W1NP+W2NP)
                XLA(NP)  = XLA1+KDX3
                YLA(NP)  = YLA1+KDY3
                IF(LA_ZCAL==1) THEN
                    ZLA(NP)  = ZLA1+KDZ3
                ELSE
                    ZLA(NP)=HPLA(NP)+BELVLA(NP)-DLA(NP)
                ENDIF
                CALL CONTAINER(XLA,YLA,ZLA,LLA,KLA,NP)
                IF (LLA(NP)<2.OR.BEDGEMOVE.OR.HPLA(NP)<=0) CYCLE
                CALL DRIFVELCAL(LLA(NP),KLA(NP),NP,U1NP,V1NP,W1NP,U2NP,V2NP,W2NP)
                KDX4 = DT*U2NP
                KDY4 = DT*V2NP
                KDZ4 = DT*W2NP
                XLA(NP) = XLA1+(KDX1+2.0*KDX2+2.0*KDX3+KDX4)/6.0
                YLA(NP) = YLA1+(KDY1+2.0*KDY2+2.0*KDY3+KDY4)/6.0
                IF(LA_ZCAL==1) THEN
                    ZLA(NP) = ZLA1+(KDZ1+2.0*KDZ2+2.0*KDZ3+KDZ4)/6.0
                ELSE
                    ZLA(NP)=HPLA(NP)+BELVLA(NP)-DLA(NP)
                ENDIF
                CALL RANDCAL(LLA(NP),KLA(NP),NP)
                CALL CONTAINER(XLA,YLA,ZLA,LLA,KLA,NP)
            ENDIF
        ENDDO


        !  MAKE CHECK WHETHER PARTICLE IS WITHIN GHOST ZONE AND IS MOVE
        IF (MPI_PAR_FLAG == 1) THEN
          CALL COMMUNICATE_DRIFTERS
        END IF

        ! *** WRITE THE CURRENT TRACK POSITION
        IF (TIMEDAY>=TIMENEXT_WRITE_DR) THEN
            IF (PARTID == MASTER_TASK) THEN
                WRITE(ULGR,*) TIMEDAY
                WRITE(ULGR,*) (XLA_ALL(NP),YLA_ALL(NP),(ZLA_ALL(NP)),NP=1,NPD_TOT)
            END IF
            FLUSH(ULGR)
            TIMENEXT_WRITE_DR = TIMENEXT_WRITE_DR+LA_FREQ
        ENDIF
    END SUBROUTINE
 
    SUBROUTINE DRIFTERINP   ! ********************************************************************
        !READING INPUT DATA OF INITIAL LOCATIONS OF DRIFTERS
        !OUTPUT: NPD,XLA,YLA,ZLA,NP=1:NPD
        !        LA_BEGTI, LA_ENDTI, LA_FREQ,LANDT
        INTEGER   ::I_XLA, J_YLA, I_XLA_IN,J_YLA_IN,L
        INTEGER(4)::NP
        REAL(RKD) ::RANVAL
        REAL RAND
        NPD = 0
        !  REAL(8),EXTERNAL::DRAND   !IT NEEDS THIS STATEMENT IN CASE OF IMPLICIT NONE
    
        OPEN(ULOC,FILE='DRIFTER.INP',ACTION='READ')
        CALL READSTR(ULOC)
        READ(ULOC,*) LA_ZCAL,LA_PRAN,LA_DIFOP,LA_HORDIF,LA_VERDIF,DEPOP !05 MAY 2009: NEW STRUCTURE
        CALL READSTR(ULOC)
        READ(ULOC,*) LA_BEGTI, LA_ENDTI, LA_FREQ            !UPDATED 23-04-09
        LA_FREQ = LA_FREQ/1440.                             !Output Frequency
        CALL READSTR(ULOC)
        READ(ULOC,*) NPD_TOT
        ! FOR PARALLEL VERSION WE NEED TO FIRST COMPUTE
        ! WE DON'T KNOW NPD YET
        ! ALLOCATE(XLA(NPD),YLA(NPD),ZLA(NPD),DLA(NPD))
        ! ALLOCATE(LLA(NPD),KLA(NPD),HPLA(NPD),BELVLA(NPD))
        ALLOCATE(XLA_ALL(NPD_TOT*2),YLA_ALL(NPD_TOT*2),ZLA_ALL(NPD_TOT*2),DLA_ALL(NPD_TOT*2))
        ALLOCATE(ILA_ALL(NPD_TOT*2),JLA_ALL(NPD_TOT*2))
        ALLOCATE(ZCTR(0:KC+1))
        XLA_ALL(:) = 0; YLA_ALL(:) = 0; ZLA_ALL(:) = 0; DLA_ALL(:) = 0
        !  LLA = 0
        !  KLA = 0
        !  HPLA= 0
        CALL READSTR(ULOC)
        IF (DEPOP==1) THEN
            DO NP=1,NPD_TOT
                 ! *** Read Depths
                READ(ULOC,*,ERR=999) XLA_ALL(NP),YLA_ALL(NP),DLA_ALL(NP) ! FOR MPI, NEED TO READ IN GLOBALLY
            ENDDO
        ELSE
            DO NP=1,NPD_TOT
                 ! *** Read Elevations
                READ(ULOC,*,ERR=999) XLA_ALL(NP),YLA_ALL(NP),ZLA_ALL(NP)
            ENDDO
        ENDIF
        CLOSE(ULOC)
        IF(LA_PRAN>0) RANVAL = RAND()
        RETURN
999     STOP 'DRIFTER.INP READING ERROR!'
    END SUBROUTINE

    SUBROUTINE READSTR(UINP)   !******************************************************************
        INTEGER(4),INTENT(IN)::UINP
        CHARACTER(200)::STR
        DO WHILE (1==1)
            READ(UINP,'(A)') STR
            STR=ADJUSTL(STR)
            IF (STR(1:1).NE.'*') THEN
                BACKSPACE(UINP)
                RETURN
            ENDIF
        ENDDO
    END SUBROUTINE

    SUBROUTINE CONTAINER(XLA,YLA,ZLA,LLA,KLA,NP)   !**********************************************
        !DETERMINING LLA,KLA,BELVLA,HPLA FOR THE FIRST CALL
        !UPDATING XLA,YLA,LLA,KLA,BELVLA,HPLA FOR THE NEXT CALL
        !FOR EACH DRIFTER (XLA,YLA,ZLA)
        !BY FINDING THE NEAREST CELL CENTTROID
        !THEN EXPANDING TO THE NEIGHBOUR CELLS
        !HP(LIJ(I,J))     : WATER DEPTH = WATER SUR. - BELV
        !BELV(LIJ(I,J))   : BOTTOM ELEVATION OF A CELL
        !BELVLA           : BED ELEVATION AT DRIFTER NI POSITION
        !HPLA             : WATER DEPTH AT DRIFTER NI POSITION
        !DLON(L),L=2:LA ? : CELL CENTROID XCEL = XCOR(L,5)
        !DLAT(L),L=2:LA ? : CELL CENTROID YCEL = YCOR(L,5)
        !DZC(K),K=1:KC    : LAYER THICKNESS
        !LIJ(1:ICM,1:JCM)
        !INPUT:
        !IF DEPOP=0: XLA,YLA,ZLA,XCOR(L,5),YCOR(L,5),BELV,HP
        !IF DEPOP=1: XLA,YLA,XCOR(L,5),YCOR(L,5),BELV,HP,DLA
        !OUTPUT:
        !  XLA,YLA,LLA(NP),KLA(NP),BELVLA(NP),HPLA(NP)
        REAL(RKD) ,INTENT(INOUT)::XLA(:),YLA(:)
        INTEGER(4),INTENT(IN),OPTIONAL::NP
        INTEGER(4),INTENT(INOUT)::LLA(:),KLA(:)
        REAL(RKD) ,INTENT(INOUT)::ZLA(:)
        INTEGER(4)::NPSTAT,LLA1,LLA2
        INTEGER(4)::NI,LMILOC(1),K,L,N1,N2,I,J,ILN,JLN
        INTEGER(4)::I1,I2,J1,J2, IDR_GL, JDR_GL
        REAL(RKD) ::RADLA(LA),SCALE ,CELL_SIZE
        LOGICAL(4)::MASK1,MASK2,MASK3,MASK4
        LOGICAL(4)::CMASK,CMASK1,CMASK2,CMASK3,CMASK4
        LOGICAL(4)::CPOS1,CPOS2,CPOS3,CPOS4
        IF (PRESENT(NP)) THEN
            N1=NP
            N2=NP
            IF (LLA(NP)<2) RETURN
        ELSE  ! DON'T KNOW COORDINATES OF I,J CELLS
            N1=1
            N2=NPD
        ENDIF
        ZCTR(0:KC)=ZZ(0:KC)
        ZCTR(KC+1)=Z(KC)
        DO NI=N1,N2
            !DETERMINE THE NEAREST CELL CENTROID
            IF (PRESENT(NP)) THEN
                !FOR THE NEXT CALL
                ILN = IL(LLA(NI))        !I OF THE CELL CONTAINING DRIFTER AT PREVIOUS TIME
                JLN = JL(LLA(NI))        !J OF THE CELL CONTAINING DRIFTER AT PREVIOUS TIME
                LLA1 = LLA(NI)           !L OF THE CELL CONTAINING DRIFTER AT PREVIOUS TIME
            ELSE
                !FOR THE FIRST CALL DRIFT    CELL_CENTRE       DRIFTER  CELL_CENTRE
                RADLA(2:LA) = SQRT((XLA(NI)-XCOR(2:LA,5))**2+(YLA(NI)-YCOR(2:LA,5))**2) !MAY 11, 2009
                LMILOC = MINLOC(RADLA(2:LA))
                ! FOR THE MPI VERSION, WE NEED A CHECK HERE THAT THE CLOSEST
                ! CELL IS ACTUALLY WITHIN THAT DOMAIN
                CELL_SIZE = SQRT( (XCOR(LMILOC(1)+1,1) - XCOR(LMILOC(1)+1,4) )**2 + (YCOR(LMILOC(1)+1,1) - YCOR(LMILOC(1)+1,2))**2)
                IF (RADLA(LMILOC(1)) < CELL_SIZE) THEN ! DRIFTER CELL IS WITHIN DOMAIN
                    ILN = (IL(LMILOC(1)+1))   !I OF THE NEAREST CELL FOR DRIFTER
                    JLN = (JL(LMILOC(1)+1))    !J OF THE NEAREST CELL FOR DRIFTER
                ELSE   ! DRIFTER CELL OUTSIDE THIS PARTITION
                    ILN = 0
                    JLN = 0
                END IF
            ENDIF
            !DETERMINE THE CELL CONTAINING THE DRIFTER WITHIN 9 CELLS: LLA(NI)   ooo
            ! 9 POINT STENCIL AROUND THE DRIFTER                                 oxo
            NPSTAT = 0             !                                             ooo
            I1 = MAX(1.d0,ILN-1.d0)
            I2 = MIN(ILN+1,ICM)
            J1 = MAX(1.d0,JLN-1.d0)
            J2 = MIN(JLN+1,JCM)
            LOOP:DO J=J1,J2
                DO I=I1,I2
                    L = LIJ(I,J)
                    IF (L<2 .OR. L > LA) CYCLE
                    !IF (INSIDECELL(L,NI)) THEN
        
                    IF (INSIDECELL(L,XLA(NI),YLA(NI))) THEN
        
        
                        IF (PRESENT(NP)) THEN
                            ! *** PARTICLE IS INSIDE CURRENT CELL
                            !DEALING WITH THE WALLS
                            MASK1 = I==ILN+1.AND.SUB(LIJ(I  ,J  ))<0.5
                            MASK2 = I==ILN-1.AND.SUB(LIJ(I+1,J  ))<0.5
                            MASK3 = J==JLN+1.AND.SVB(LIJ(I  ,J  ))<0.5
                            MASK4 = J==JLN-1.AND.SVB(LIJ(I  ,J+1))<0.5
            
                            CMASK1=(SUB(LIJ(ILN+1,JLN  ))<0.5.AND.SVB(LIJ(ILN  ,JLN+1))<0.5)
                            CMASK2=(SUB(LIJ(ILN  ,JLN  ))<0.5.AND.SVB(LIJ(ILN  ,JLN+1))<0.5)
                            CMASK3=(SUB(LIJ(ILN  ,JLN  ))<0.5.AND.SVB(LIJ(ILN  ,JLN  ))<0.5)
                            CMASK4=(SUB(LIJ(ILN+1,JLN  ))<0.5.AND.SVB(LIJ(ILN  ,JLN  ))<0.5)
            
                            CPOS1 = (I>=ILN  .AND.J==JLN+1).OR.(I==ILN+1.AND.J>=JLN  )
                            CPOS2 = (I==ILN-1.AND.J>=JLN  ).OR.(I<=ILN  .AND.J==JLN+1)
                            CPOS3 = (I==ILN-1.AND.J<=JLN  ).OR.(I<=ILN  .AND.J==JLN-1)
                            CPOS4 = (I>=ILN  .AND.J==JLN-1).OR.(I==ILN+1.AND.J<=JLN  )

                            CMASK = (CMASK1.AND.CPOS1).OR.(CMASK2.AND.CPOS2).OR.&
                                (CMASK3.AND.CPOS3).OR.(CMASK4.AND.CPOS4)

                            SCALE=1
                      
                            IF    ((MASK1.OR.MASK2).AND..NOT.CMASK) THEN
                                CALL EDGEMOVE(LLA1,NI,ILN,JLN,1,SCALE)

                            ELSEIF((MASK3.OR.MASK4).AND..NOT.CMASK) THEN
                                CALL EDGEMOVE(LLA1,NI,ILN,JLN,2,SCALE)

                            ELSEIF(CMASK1.AND.CPOS1) THEN
                                CALL EDGEMOVE(LLA1,NI,ILN,JLN,5,SCALE)
              
                            ELSEIF(CMASK2.AND.CPOS2) THEN
                                CALL EDGEMOVE(LLA1,NI,ILN,JLN,6,SCALE)
              
                            ELSEIF(CMASK3.AND.CPOS3) THEN
                                CALL EDGEMOVE(LLA1,NI,ILN,JLN,7,SCALE)

                            ELSEIF(CMASK4.AND.CPOS4) THEN
                                CALL EDGEMOVE(LLA1,NI,ILN,JLN,8,SCALE)
    
                            ELSE
                                LLA(NI)=L
                            ENDIF

                        ELSE !FIRST CALL
                            LLA(NI)=L
                        ENDIF
                        NPSTAT = 1
                        EXIT LOOP
                    ENDIF
                ENDDO
            ENDDO LOOP
    
            ! *** CHECK IF THE PARTICLE IS INSIDE THE MODEL DOMAIN
            IF (NPSTAT==0.AND.PRESENT(NP)) THEN
                ! *** PARTICLE IS OUTSIDE DOMAIN
                ! *** RECOMPUTE THE DISTANCE OF NEW POSITION
                ! *** SO THAT IT IS BACK TO PREVIOUS CELL ON THE BORDER
                MASK1 = LIJ(ILN+1,JLN  )>=2.AND.LIJ(ILN+1,JLN  )<=LA
                MASK2 = LIJ(ILN-1,JLN  )>=2.AND.LIJ(ILN-1,JLN  )<=LA
                MASK3 = LIJ(ILN  ,JLN+1)>=2.AND.LIJ(ILN  ,JLN+1)<=LA
                MASK4 = LIJ(ILN  ,JLN-1)>=2.AND.LIJ(ILN  ,JLN-1)<=LA
                SCALE = 1
      
                IF     (MASK1.AND.MASK2.AND..NOT.(MASK3.AND.MASK4)) THEN
                    CALL EDGEMOVE(LLA1,NI,ILN,JLN,2,SCALE)
        
                ELSEIF (MASK3.AND.MASK4.AND..NOT.(MASK1.AND.MASK2)) THEN
                    CALL EDGEMOVE(LLA1,NI,ILN,JLN,1,SCALE)
     
                ELSEIF (MASK1.AND.MASK4.AND..NOT.(MASK2.OR.MASK3)) THEN
                    CALL EDGEMOVE(LLA1,NI,ILN,JLN,6,SCALE)

                ELSEIF (MASK2.AND.MASK4.AND..NOT.(MASK1.OR.MASK3)) THEN
                    CALL EDGEMOVE(LLA1,NI,ILN,JLN,5,SCALE)

                ELSEIF (MASK1.AND.MASK3.AND..NOT.(MASK2.OR.MASK4)) THEN
                    CALL EDGEMOVE(LLA1,NI,ILN,JLN,7,SCALE)

                ELSEIF (MASK2.AND.MASK3.AND..NOT.(MASK1.OR.MASK4)) THEN
                    CALL EDGEMOVE(LLA1,NI,ILN,JLN,8,SCALE)

                ELSE
                    CALL EDGEMOVE(LLA1,NI,ILN,JLN,0,SCALE)
                ENDIF
      
                LLA2=LLA(NI)
                IF (ANY(LPBN==LLA(NI)).OR.ANY(LPBS==LLA(NI)).OR. &
                    ANY(LPBE==LLA(NI)).OR.ANY(LPBW==LLA(NI)))   THEN
                    CALL SET_DRIFTER_OUT
                    PRINT '(A36,I6)','OPEN BOUNDARY, DRIFTER IS OUTSIDE:',NI

                ELSEIF(ANY(LQS==LLA(NI)).AND.QSUM(LLA(NI),KLA(NI))<0) THEN
                    CALL SET_DRIFTER_OUT
                    PRINT '(A36,I6)','WITHDAWAL CELL, DRIFTER IS OUTSIDE:',NI

                ELSEIF (ANY(IQWRU==IL(LLA(NI))).AND.ANY(JQWRU==JL(LLA(NI)))) THEN
                    CALL SET_DRIFTER_OUT
                    ! ***  RETURN DRIFTER
                    DO K=1,NQWR
                        IF( IQWRU(K)==IL(LLA2).AND.JQWRU(K)==JL(LLA2).AND.KQWRU(K)==KLA(NI) ) THEN
                            LLA(NI)=LIJ(IQWRD(K),JQWRD(K))
                            LLA2=LLA(NI)
                            XLA(NI)= XCOR(LLA2,5)
                            YLA(NI)= YCOR(LLA2,5)
                            ZLA(NI)= BELVLA(LLA2)+HPLA(LLA2)*ZZ(KQWRD(K))
                            BEDGEMOVE = .TRUE.
                            EXIT
                        ENDIF
                    ENDDO
                    IF( LLA(NI)==1 )THEN
                        PRINT '(A36,I6)','WITHDRAWAL/RETURN, DRIFTER IS OUTSIDE:',NI
                    ENDIF

                ELSEIF (ANY(IQCTLU==IL(LLA(NI))).AND.ANY(JQCTLU==JL(LLA(NI)))) THEN
                    ! *** HYDRAULIC STRUCTURE.  RETURN DRIFTER TO DOWNSTREAM CELL, IF ANY
                    CALL SET_DRIFTER_OUT
                    ! ***  RETURN DRIFTER, IF POSSIBLE
                    DO K=1,NQCTL
                        IF( IQCTLU(K)==IL(LLA2).AND.JQCTLU(K)==JL(LLA2) .AND. IQCTLD(K)>0 ) THEN
                            LLA(NI)=LIJ(IQCTLD(K),JQCTLD(K))
                            XLA(NI)= XCOR(LLA(NI),5)
                            YLA(NI)= YCOR(LLA(NI),5)
                            ZLA(NI)= BELVLA(LLA(NI))+HPLA(LLA(NI))/2.
                            BEDGEMOVE = .TRUE.
                            EXIT
                        ENDIF
                    ENDDO
                    IF( LLA(NI)==1 )THEN
                        PRINT '(A40,I6)','HYDRAULIC STRUCTURE, DRIFTER IS OUTSIDE:',NI
                    ENDIF
        
                ENDIF
      
            ELSEIF (NPSTAT==0.AND..NOT.PRESENT(NP)) THEN
                !FOR THE FIRST CALL
                LLA(NI)=1

            ENDIF
            !DETERMINE BOTTOM ELEVATION AND TOTAL WATER DEPTH OF DRIFTERS FOR EVERYTIME
            IF (LLA(NI)>=2) CALL DRIFTERWDEP(LLA(NI),NI,BELVLA(NI),HPLA(NI))
        
            !CONVERT DLA TO ZLA
            IF (.NOT.PRESENT(NP).AND.DEPOP==1) ZLA(NI)=HPLA(NI)+BELVLA(NI)-DLA(NI)
            IF (MPI_PAR_FLAG==1.AND.DEPOP==1) ZLA(NI)=HPLA(NI)+BELVLA(NI)-DLA(NI)


            IF (LLA(NI)>=2) THEN
                CALL DRIFTERLAYER(LLA(NI),NI,BELVLA(NI),HPLA(NI),KLA(NI),ZLA(NI))
            ENDIF
    
        ENDDO

    CONTAINS
        SUBROUTINE SET_DRIFTER_OUT
            XLA(NI)= XLA1
            YLA(NI)= YLA1
            ZLA(NI)= ZLA1
            LLA(NI)= 1
        END SUBROUTINE
   
    END SUBROUTINE

    SUBROUTINE AREACAL(XC,YC,AREA)   ! ***********************************************************
        !AREA CALCULATION OF A POLYGON
        !WITH GIVEN VEXTICES (XC,YC)
        REAL(RKD),INTENT(IN) ::XC(:),YC(:)
        REAL(RKD),INTENT(OUT)::AREA
        REAL(RKD)::XVEC(2),YVEC(2)
        INTEGER(4)::NPOL,K
        NPOL = SIZE(XC)
        AREA = 0
        XVEC(1)=XC(2)-XC(1)
        YVEC(1)=YC(2)-YC(1)
        DO K=3,NPOL
            XVEC(2) = XC(K)-XC(1)
            YVEC(2) = YC(K)-YC(1)
            AREA = AREA+0.5*ABS( XVEC(1)*YVEC(2)-XVEC(2)*YVEC(1))
            XVEC(1)=XVEC(2)
            YVEC(1)=YVEC(2)
        ENDDO
    END SUBROUTINE

    SUBROUTINE DRIFVELCAL(LNI,KNI,NI,U1NI,V1NI,W1NI,U2NI,V2NI,W2NI)   ! **************************
        !CALCULATING VELOCITY COMPONENTS AT DRIFTER LOCATION
        !BY USING INVERSE DISTANCE POWER 2 INTERPOLATION
        !FOR VELOCITY COMPONENTS AT THE CENTROID OF POLYGON
        INTEGER(4),INTENT(IN )::LNI,KNI,NI
        REAL(RKD) ,INTENT(OUT)::U1NI,V1NI,W1NI,U2NI,V2NI,W2NI
        INTEGER(4)::ICELL,JCELL,I,J,L,LN,K1,K2,KZ1,KZ2
        REAL(RKD)::RAD2,SU1,SU2,SU3,SV1,SV2,SV3,SW1,SW2,SW3
        REAL(RKD)::UTMPB,VTMPB,UTMPB1,VTMPB1,WTMPB,WTMPB1
        REAL(RKD)::VELEK,VELNK,VELEK1,VELNK1,ZSIG
        REAL(RKD)::UKB,UKT,VKB,VKT,UKB1,UKT1,VKB1,VKT1
        LOGICAL(4)::CRN1,CRN2,CRN3,CRN4

        ICELL = IL(LNI)
        JCELL = JL(LNI)
        SU1=0
        SU2=0
        SU3=0
        SV1=0
        SV2=0
        SV3=0
        SW1=0
        SW2=0
        SW3=0
        DO J=JCELL-1,JCELL+1
            DO I=ICELL-1,ICELL+1
                L = LIJ(I,J)
                IF (L.GE.2) THEN
                    LN   = LNC(L)           !L index of the cell above (North)
                    CRN1 = I==ICELL+1.AND.SUB(LIJ(I  ,J  ))<0.5
                    CRN2 = I==ICELL-1.AND.SUB(LIJ(I+1,J  ))<0.5
                    CRN3 = J==JCELL-1.AND.SVB(LIJ(I  ,J+1))<0.5
                    CRN4 = J==JCELL+1.AND.SVB(LIJ(I  ,J  ))<0.5
                    IF (CRN1.OR.CRN2.OR.CRN3.OR.CRN4) CYCLE

                    !CALCULATING HOR.VELOCITY COMPONENTS AT CENTROID
                    RAD2 = MAX((XLA(NI)-XCOR(L,5))**2+(YLA(NI)-YCOR(L,5))**2,1D-8)
                    ZSIG = (ZLA(NI)-BELVLA(NI))/HPLA(NI)
                    ZSIG = MAX(0.d0,MIN(1.d0,ZSIG))
                    ZLA(NI)=ZSIG*HPLA(NI)+BELVLA(NI)
                    IF(ZSIG>=ZZ(KNI)) THEN
                        K1 = KNI
                        K2 = MIN(KNI+1,KC)
                        KZ1= KNI
                        KZ2= KNI+1
                    ELSE
                        K1 = MAX(1,KNI-1)
                        K2 = KNI
                        KZ1= KNI-1
                        KZ2= KNI
                    ENDIF
                    UKB =0.5*STCUV(L)*(RSSBCE(L)*U (LEAST(L),K1)*SUB(LEAST(L))+RSSBCW(L)*U (L,K1)*SUB(L))
                    UKB1=0.5*STCUV(L)*(RSSBCE(L)*U1(LEAST(L),K1)*SUB(LEAST(L))+RSSBCW(L)*U1(L,K1)*SUB(L))
                    VKB =0.5*STCUV(L)*(RSSBCN(L)*V (LN, K1)*SVB(LN) +RSSBCS(L)*V (L,K1)*SVB(L))
                    VKB1=0.5*STCUV(L)*(RSSBCN(L)*V1(LN, K1)*SVB(LN) +RSSBCS(L)*V1(L,K1)*SVB(L))

                    UKT =0.5*STCUV(L)*(RSSBCE(L)*U (LEAST(L),K2)*SUB(LEAST(L))+RSSBCW(L)*U (L,K2)*SUB(L))
                    UKT1=0.5*STCUV(L)*(RSSBCE(L)*U1(LEAST(L),K2)*SUB(LEAST(L))+RSSBCW(L)*U1(L,K2)*SUB(L))
                    VKT =0.5*STCUV(L)*(RSSBCN(L)*V (LN, K2)*SVB(LN) +RSSBCS(L)*V (L,K2)*SVB(L))
                    VKT1=0.5*STCUV(L)*(RSSBCN(L)*V1(LN, K2)*SVB(LN) +RSSBCS(L)*V1(L,K2)*SVB(L))

                    UTMPB = (UKT -UKB )*(ZSIG-ZCTR(KZ1))/(ZCTR(KZ2)-ZCTR(KZ1))+UKB
                    UTMPB1= (UKT1-UKB1)*(ZSIG-ZCTR(KZ1))/(ZCTR(KZ2)-ZCTR(KZ1))+UKB1
                    VTMPB = (VKT -VKB )*(ZSIG-ZCTR(KZ1))/(ZCTR(KZ2)-ZCTR(KZ1))+VKB
                    VTMPB1= (VKT1-VKB1)*(ZSIG-ZCTR(KZ1))/(ZCTR(KZ2)-ZCTR(KZ1))+VKB1
        
                    !INTERPOLATION FOR VERTICAL VELOCITY COMPONENT
                    WTMPB = (W (L,KNI)-W (L,KNI-1))*(ZSIG-Z(KNI-1))/(Z(KNI)-Z(KNI-1))+W (L,KNI-1)
                    WTMPB1= (W1(L,KNI)-W1(L,KNI-1))*(ZSIG-Z(KNI-1))/(Z(KNI)-Z(KNI-1))+W1(L,KNI-1)

                    !ROTATION
                    VELEK=CUE(L)*UTMPB+CVE(L)*VTMPB
                    VELNK=CUN(L)*UTMPB+CVN(L)*VTMPB
                    VELEK1=CUE(L)*UTMPB1+CVE(L)*VTMPB1
                    VELNK1=CUN(L)*UTMPB1+CVN(L)*VTMPB1
                    SU1=SU1+VELEK1/RAD2
                    SU2=SU2+VELEK /RAD2
                    SU3=SU3+1._8/RAD2
                    SV1=SV1+VELNK1/RAD2
                    SV2=SV2+VELNK /RAD2
                    SV3=SV3+1._8/RAD2
                    SW1=SW1+WTMPB1/RAD2
                    SW2=SW2+WTMPB /RAD2
                    SW3=SW3+1._8/RAD2

                ENDIF
            ENDDO
        ENDDO
        U1NI = SU1/SU3
        U2NI = SU2/SU3
        V1NI = SV1/SV3
        V2NI = SV2/SV3
        W1NI = SW1/SW3
        W2NI = SW2/SW3

    END SUBROUTINE

    SUBROUTINE RANDCAL(L,K,NP)   ! ***************************************************************
        INTEGER,INTENT(IN)::L,K,NP
        !  REAL(8),EXTERNAL::DRAND
        REAL(RKD)::COEF
        REAL RAND
        IF (LA_PRAN==1.OR.LA_PRAN==3) THEN
            IF (LA_DIFOP==0) THEN
                COEF = SQRT(2*AH(L,K)*DT)
            ELSE
                COEF = SQRT(2*LA_HORDIF*DT)
            ENDIF
            XLA(NP) = XLA(NP) + (2*RAND()-1)*COEF
            YLA(NP) = YLA(NP) + (2*RAND()-1)*COEF
        ENDIF
        IF (LA_PRAN.GE.2.AND.LA_ZCAL==1) THEN
            IF (LA_DIFOP==0) THEN
                COEF = SQRT(2*AV(L,K)*DT)
            ELSE
                COEF = SQRT(2*LA_VERDIF*DT)
            ENDIF
            ZLA(NP) = ZLA(NP)+ (2*RAND()-1)*COEF
        ENDIF
    END SUBROUTINE

    SUBROUTINE EDGEMOVE(LLA1,NI,ILN,JLN,NCASE,SCALE)    ! ****************************************
        !I,J,L:INDICES OF DRIFTER AT CURRENT POSITION
        INTEGER(4),INTENT(IN)::LLA1,NI,ILN,JLN,NCASE
        REAL(RKD), INTENT(IN)::SCALE
        REAL(RKD)::UTMPB,VTMPB,VELM
        INTEGER(4)::LN,KLA1

        KLA1 = KLA(NI)
        LN = LNC(LLA1)  !
        UTMPB = 0.5*STCUV(LLA1)*(RSSBCE(LLA1)*U1(LLA1+1,KLA(NI))+RSSBCW(LLA1)*U1(LLA1,KLA(NI)))
        VTMPB = 0.5*STCUV(LLA1)*(RSSBCN(LLA1)*V1(LN,    KLA(NI))+RSSBCS(LLA1)*V1(LLA1,KLA(NI)))
        VELM  = SCALE*MAX(ABS(UTMPB),ABS(VTMPB),1.D-2)

        IF (NCASE==1) THEN
            ! *** MOVE ALONG THE V DIRECTTION
            !UTMPB = -SCALE*UTMPB
            UTMPB = -SIGNV(UTMPB)*VELM
            IF (ABS(UTMPB)<1.D-2) UTMPB = 1.D-2*SIGNV(UTMPB)
            CALL RESET_LLA(ILN,ILN,JLN-1,JLN+1)
            IF (BEDGEMOVE) RETURN
            UTMPB = -UTMPB
            CALL RESET_LLA(ILN,ILN,JLN-1,JLN+1)
            IF (BEDGEMOVE) RETURN

        ELSEIF (NCASE==2) THEN
            ! *** MOVE ALONG THE U DIRECTTION
            !VTMPB = -SCALE*VTMPB
            VTMPB = -SIGNV(VTMPB)*VELM
            IF (ABS(VTMPB)<1.D-2) VTMPB = 1.D-2*SIGNV(VTMPB)
            CALL RESET_LLA(ILN-1,ILN+1,JLN,JLN)
            IF (BEDGEMOVE) RETURN
            VTMPB = -VTMPB
            CALL RESET_LLA(ILN-1,ILN+1,JLN,JLN)
            IF (BEDGEMOVE) RETURN

        ELSEIF (NCASE==5) THEN
            !UPPER-R CORNER IS LIMITTED
            UTMPB = -VELM
            VTMPB = -VELM
            CALL RESET_LLA(ILN-1,ILN,JLN-1,JLN)
            IF (BEDGEMOVE) RETURN

        ELSEIF (NCASE==6) THEN
            !UPER-L CORNER IS LIMITTED
            UTMPB =  VELM
            VTMPB = -VELM
            CALL RESET_LLA(ILN,ILN+1,JLN-1,JLN)
            IF (BEDGEMOVE) RETURN

        ELSEIF (NCASE==7) THEN
            !LOWER-L CORNER IS LIMITTED
            UTMPB = VELM
            VTMPB = VELM
            CALL RESET_LLA(ILN,ILN+1,JLN,JLN+1)
            IF (BEDGEMOVE) RETURN

        ELSEIF (NCASE==8) THEN
            !LOWER-R CORNER IS LIMITTED
            UTMPB = -VELM
            VTMPB =  VELM
            CALL RESET_LLA(ILN-1,ILN,JLN,JLN+1)
            IF (BEDGEMOVE) RETURN

        ENDIF

        XLA(NI)= XLA1
        YLA(NI)= YLA1
        ZLA(NI)= ZLA1
        LLA(NI)= LLA1
  
    CONTAINS
        SUBROUTINE RESET_LLA(I1,I2,J1,J2)
            INTEGER(4),INTENT(IN)::I1,I2,J1,J2
            INTEGER(4)::I,J,L
            REAL(RKD)::VELEK,VELNK

            VELEK =CUE(LLA1)*UTMPB+CVE(LLA1)*VTMPB
            VELNK =CUN(LLA1)*UTMPB+CVN(LLA1)*VTMPB
            XLA(NI)=XLA1+ DT*VELEK
            YLA(NI)=YLA1+ DT*VELNK
            DO J=J1,J2
                DO I=I1,I2
                    L = LIJ(I,J)
                    IF (L<2) CYCLE
                    !IF (INSIDECELL(L,NI)) THEN
       
                    IF (INSIDECELL(L,XLA(NI),YLA(NI))) THEN

                        LLA(NI)=L
                        BEDGEMOVE = .TRUE.
                        RETURN
                    ENDIF
                ENDDO
            ENDDO
        END SUBROUTINE
  
    END SUBROUTINE

    FUNCTION INSIDECELL(L,XM,YM) RESULT(INSIDE)   ! **********************************************
        LOGICAL(4)::INSIDE
        INTEGER(4),INTENT(IN)::L
        REAL(RKD) ,INTENT(IN)::XM,YM
        REAL(RKD) ::XC(6),YC(6),AREA2

        XC(1) = XM
        YC(1) = YM
        XC(2:5)=XCOR(L,1:4)
        YC(2:5)=YCOR(L,1:4)
        XC(6) = XC(2)
        YC(6) = YC(2)
        CALL AREACAL(XC,YC,AREA2)
        IF (ABS(AREA2-AREA(L))<=1E-6) THEN
            INSIDE=.TRUE.
        ELSE
            INSIDE=.FALSE.
        ENDIF
    END FUNCTION

    SUBROUTINE DRIFTERWDEP(LNI,NI,BELVNI,HPNI)   !************************************************
        !INTERPOLATION OF THE TOTAL WATER DEPTH AND BOTTOM ELEVATION
        !FOR THE DRIFTER NI AT EACH TIME INSTANT AND EACH LOCATION
        INTEGER(4),INTENT(IN)::LNI,NI
        REAL(RKD),INTENT(OUT)::BELVNI,HPNI
        INTEGER(4)::ICELL,JCELL,L,I,J
        REAL(RKD) ::BELVNI1,BELVNI2,RAD2,ZETA

        ICELL = IL(LNI)
        JCELL = JL(LNI)
        BELVNI1=0
        BELVNI2=0
        DO J=JCELL-1,JCELL+1
            DO I=ICELL-1,ICELL+1
                L = LIJ(I,J)
                IF (L.GE.2) THEN
                    RAD2 = MAX((XLA(NI)-XCOR(L,5))**2+(YLA(NI)-YCOR(L,5))**2,1D-8)
                    BELVNI1=BELVNI1+BELV(L)/RAD2
                    BELVNI2=BELVNI2+1._8/RAD2
                ENDIF
            ENDDO
        ENDDO
        BELVNI = BELVNI1/BELVNI2
        ZETA = HP(LNI)+BELV(LNI)
        HPNI = ZETA-BELVNI

    END SUBROUTINE

    SUBROUTINE DRIFTERLAYER(LNI,NI,BELVNI,HPNI,KLN,ZLN)
        !RECALCULATE ZLA(NI)
        !DETERMINE KLA(NI)
        INTEGER(4),INTENT(IN)::LNI,NI
        REAL(RKD), INTENT(IN)::BELVNI,HPNI
        INTEGER(4),INTENT(OUT)::KLN
        REAL(RKD), INTENT(INOUT)::ZLN
        INTEGER(4)::K
        REAL(RKD) ::ZSIG
        IF (LNI.GE.2) THEN
            ZSIG = (ZLN-BELVNI)/HPNI
            ZSIG = MAX(0.d0,MIN(1.d0,ZSIG))
            ZLN=ZSIG*HPNI+BELVNI  !IF ZSIG>1 OR ZSIG<0
            DO K=1,KC
                IF(SUM(DZC(1:K))>=ZSIG) THEN
                    KLN = K
                    EXIT
                ENDIF
            ENDDO
        ENDIF
    END SUBROUTINE

    FUNCTION SIGNV(V)
        REAL(RKD),INTENT(IN)::V
        INTEGER(4)::SIGNV
        IF (V>=0) THEN
            SIGNV= 1
        ELSE
            SIGNV=-1
        ENDIF
    END FUNCTION

    SUBROUTINE AREA_CENTRD
        !DETERMINING CELLCENTROID OF ALL CELLS
        !AND CALCULATING THE AREA OF EACH CELL
        INTEGER(4)::I,J,K,L
        REAL(RKD)::XC(4),YC(4),AREA2
        XCOR = 0
        YCOR = 0
        AREA = 0
        !! COMPUTE XCOR & YCOR BASED ON INFORMATION FROM LXLY.INP & DXDY.INP
        DO L = 2, LA
            XCOR(L,1) = DLON(L) - DXP(L)/2;  YCOR(L,1) = DLAT(L) - DYP(L)/2   ! (X-0.5, Y-0.5)
            XCOR(L,2) = DLON(L) - DXP(L)/2;  YCOR(L,2) = DLAT(L) + DYP(L)/2   ! (X-0.5, Y+0.5)
            XCOR(L,3) = DLON(L) + DXP(L)/2;  YCOR(L,3) = DLAT(L) + DYP(L)/2   ! (X+0.5, Y+0.5)
            XCOR(L,4) = DLON(L) + DXP(L)/2;  YCOR(L,4) = DLAT(L) - DYP(L)/2   ! (X+0.5, Y-0.5)
            XC(1:4) = XCOR(L,1:4)
            YC(1:4) = YCOR(L,1:4)
            CALL AREACAL(XC,YC,AREA2)
            AREA(L) = AREA2
            ! *** STORE THE CELL CENTROID IN INDEX=5
            XCOR(L,5) = 0.25*SUM(XC)
            YCOR(L,5) = 0.25*SUM(YC)
        ENDDO
        PRINT *,'DRIFTER: NUMBER OF DRIFTERS INITIALZED: ',NPD
100     CLOSE(UCOR)
        RETURN
998     STOP 'CORNERS.INP READING ERROR!'
    END SUBROUTINE
 


    SUBROUTINE MAP_GLOBAL_LOCAL(CHECK_WHETHER_IN_GHOST_CELLS) !!(XLA, YLA, ZLA, XLA_ALL,YLA_ALL,ZLA_ALL)

         !  XLA,YLA,LLA(NP),KLA(NP),BELVLA(NP),HPLA(NP)
        !        REAL(RKD) ,INTENT(IN)::XLA_ALL(:),YLA_ALL(:), ZLA_ALL(:)
        !        REAL(RKD) , INTENT(OUT)::XLA(:),YLA(:), ZLA(:)
        INTEGER(4)::NPSTAT,LLA1,LLA2,COMM_FLAG,ERROR, CHECK_WHETHER_IN_GHOST_CELLS
        INTEGER(4)::NI,LMILOC(1),K,L,N1,N2,I,J,ILN,JLN
        INTEGER(4)::I1,I2,J1,J2, IDR_GL, JDR_GL,NPD_LOC
        REAL(RKD) ::RADLA(LA),SCALE ,CELL_SIZE
        IF(ALLOCATED(XLA))THEN
            ! NUMBER OF DRIFTERS IN EACH PARTITION CAN CHANGE EACH TIMESTEP
            DEALLOCATE (XLA, YLA, ZLA, LLA, DLA, KLA , HPLA, BELVLA)
        END IF
        ALLOCATE (XLA(0), YLA(0), ZLA(0), LLA(0) )
        N1=1
        N2=NPD_TOT
        NPD = 0
        DO NI=N1,N2

            !FOR THE FIRST CALL DRIFT    CELL_CENTRE       DRIFTER  CELL_CENTRE
            RADLA(2:LA) = SQRT((XLA_ALL(NI)-XCOR(2:LA,5))**2+(YLA_ALL(NI)-YCOR(2:LA,5))**2) !MAY 11, 2009
            LMILOC = MINLOC(RADLA(2:LA))
            ! FOR THE MPI VERSION, WE NEED A CHECK HERE THAT THE CLOSEST
            ! CELL IS ACTUALLY WITHIN THAT DOMAIN
            CELL_SIZE = SQRT( (XCOR(LMILOC(1)+1,1) - XCOR(LMILOC(1)+1,4) )**2 + (YCOR(LMILOC(1)+1,1) - YCOR(LMILOC(1)+1,2))**2)
            IF (RADLA(LMILOC(1)) < CELL_SIZE*1.2) THEN ! DRIFTER CELL IS WITHIN DOMAIN
                ILN = (IL(LMILOC(1)+1))   !I OF THE NEAREST CELL FOR DRIFTER
                JLN = (JL(LMILOC(1)+1))    !J OF THE NEAREST CELL FOR DRIFTER
            ELSE   ! DRIFTER CELL OUTSIDE THIS PARTITION
                ILN = 0
                JLN = 0
            END IF
            !DETERMINE THE CELL CONTAINING THE DRIFTER WITHIN 9 CELLS: LLA(NI)   ooo
            ! 9 POINT STENCIL AROUND THE DRIFTER                                 oxo
            NPSTAT = 0             !                                             ooo
            I1 = MAX(1.d0,ILN-1.d0)
            I2 = MIN(ILN+1,ICM)
            J1 = MAX(1.d0,JLN-1.d0)
            J2 = MIN(JLN+1,JCM)
            LOOP:DO J=J1,J2
                DO I=I1,I2
                    L = LIJ(I,J)
                    IF (L<2 .OR. L > LA) CYCLE
                    IF (INSIDECELL(L,XLA_ALL(NI),YLA_ALL(NI))) THEN
                            IF (.NOT. GHOSTZONE(L)) THEN
                                NPD = NPD + 1 ! Create Temp arrays that are then distributed via call to MPI_Communicate
                                XLA = [XLA, XLA_ALL(NI)]
                                YLA = [YLA, YLA_ALL(NI)]
                                ZLA = [ZLA, ZLA_ALL(NI)]
                                LLA = [LLA, L]
                            ENDIF
                        NPSTAT = 1
                        EXIT LOOP
                    END IF
                !                    END IF
                ENDDO   ! DO I1, I2
            ENDDO LOOP  !

        END DO


        ALLOCATE(DLA(NPD))
        ALLOCATE(KLA(NPD),HPLA(NPD),BELVLA(NPD))
        DLA=0.
        KLA=0
        HPLA=0.
        BELVLA=0.


        DO NP=1,NPD
            !DETERMINE BOTTOM ELEVATION AND TOTAL WATER DEPTH OF DRIFTERS FOR EVERYTIME
            IF (LLA(NP)>=2) CALL DRIFTERWDEP(LLA(NP),NP,BELVLA(NP),HPLA(NP))

            IF (LLA(NP)>=2) CALL DRIFTERLAYER(LLA(NP),NP,BELVLA(NP), &
                HPLA(NP),KLA(NP),ZLA(NP))
        END DO


    END SUBROUTINE

    SUBROUTINE COMMUNICATE_DRIFTERS! (XLA, YLA, ZLA, XLA_ALL, YLA_ALL, ZLA_ALL)   !**********************************************
!! This is only related to MPI implementation of code. Not necessary otherwise
#ifdef key_mpi
        ! WE PACK THE THREE DRIFTER COMPONENTS (XLA, YLA and ZLA) INTO A
        ! SINGLE ARRAY, DISTRIBUTE TO ALL PROCESSORS USING MPI_ALLGATHER.
        ! UNPACK LOCALLY AND FOR EACH PROCESSOR IDENTIFY IF WITHIN SUBDOMAIN
        ! BASED ON GLOBAL (I,J) INDICES
        !        REAL(RKD) ,ALLOCATABLE, INTENT(INOUT)::XLA(:),YLA(:), ZLA(:)
        !        REAL(RKD) ,INTENT(out):: XLA_ALL(:), YLA_ALL(:), ZLA_ALL(:)
        REAL(RKD) ,ALLOCATABLE::DRIFT_PACK_LOCAL(:), DRIFT_PACK_GLOBAL(:)
        INTEGER(4), ALLOCATABLE:: DISPLS(:),RCOUNTS(:)
        INTEGER(4):: ERROR,i, IBEGIN, IEND, ISTEP, XL_IBEG, XL_END, L_TEMP, ILA_LOC, JLA_LOC
        INTEGER(4),ALLOCATABLE::PROC_SIZE_ARR(:)       !SIZE OF ARRAY ON EACH PROC FOR DRIFTER GATHER
        IF(ALLOCATED(DRIFT_PACK_LOCAL)) THEN
            DEALLOCATE(DRIFT_PACK_LOCAL)
            DEALLOCATE(DRIFT_PACK_GLOBAL)
        END IF
        ALLOCATE(DRIFT_PACK_LOCAL(NPD*5),STAT=ERROR)
        IF(.NOT.ALLOCATED(PROC_SIZE_ARR))THEN
            ALLOCATE(PROC_SIZE_ARR(NPARTS),STAT=ERROR)
            ALLOCATE(displs(NPARTS),STAT=ERROR)
            ALLOCATE(rcounts(NPARTS),STAT=ERROR)
            IF(ERROR.NE.0) WRITE(*,*) 'ALLOCATION ERROR DRIFT_PACK'
        END IF
        DRIFT_PACK_LOCAL(:) = 0.
        DRIFT_PACK_LOCAL(1:NPD)  = XPAR(IL(LLA(:)))  ! \  GLOBAL COORDINATES FOR I&J
        DRIFT_PACK_LOCAL(NPD+1: 2*NPD)  = YPAR(JL(LLA(:)))  ! /  FOR DRIFTER LOCATIONS

        DRIFT_PACK_LOCAL((2*NPD+1): 3*NPD)  = XLA(:)
        DRIFT_PACK_LOCAL((3*NPD+1): 4*NPD) = YLA(:)
        DRIFT_PACK_LOCAL((4*NPD+1): 5*NPD) = ZLA(:)
        DO I= 1, NPARTS
            DISPLS(I) = (I-1)   ! INDEX
            RCOUNTS(I) = 1
        ENDDO
        CALL MPI_ALLGATHERv(NPD, 1, MPI_INTEGER, PROC_SIZE_ARR, rcounts,displs, &
            MPI_INTEGER, MPI_COMM_WORLD, ERROR)
        IF (ERROR /= 0 ) THEN
            PRINT '(A48)','ERROR DOING A GATHER OF NPD SIZE FOR DRIFTER MODULE'
            PRINT '(A12,I6, A36, I6)','PARTITION = ', PARTID, ' COMMUNICATED NPD SIZES = ', RCOUNTS
        END IF


        DO I=1,NPARTS
            DISPLS(I) = (I-1)*(PROC_SIZE_ARR(I-1)*5) ! DISPLACEMENT INDEX FOR COMMUNICATION (ARRAY OF SIZE NPARTITION)
            RCOUNTS(I) =  PROC_SIZE_ARR(I)*5         ! SIZE OF EACH ARRAY COMMUNICATED (ARRAY 0F SIZE NPARTITION
        ENDDO
        ALLOCATE(DRIFT_PACK_GLOBAL(sum(PROC_SIZE_ARR)*5),STAT=ERROR)
        DRIFT_PACK_GLOBAL(:) = 0.
        CALL MPI_ALLGATHERv(DRIFT_PACK_LOCAL, NPD*5, MPI_REAL8, DRIFT_PACK_GLOBAL, rcounts,displs, MPI_REAL8, MPI_COMM_WORLD, ERROR)
        IF (ERROR /= 0 ) THEN
            PRINT '(A48)','ERROR DOING AN MPI GATHER OF ALL PARTICLES FOR DRIFTER MODULE'
            PRINT '(A12,I6, A36, f8.3)','PARTITION = ', PARTID, ' AND ',' COMMUNICATED PARTICLES = ', DRIFT_PACK_LOCAL
        END IF
        ILA_ALL(:) = 0.
        JLA_ALL(:) = 0.
        XLA_ALL(:) = 0.
        YLA_ALL(:) = 0.
        ZLA_ALL(:) = 0.

        ! UNPACK INTO GLOBAL XLA AND YLA AND REMAP TO PARTITIONS
        IBEGIN = 1
        XL_IBEG = 1
        DO I =1,NPARTS
            IBEGIN = IBEGIN + DISPLS(I)
            XL_IBEG = XL_IBEG + (DISPLS(I)/5)
            XL_END  = XL_IBEG + (RCOUNTS(I)/5) -1
            ISTEP = (RCOUNTS(I)/5)
            IEND = IBEGIN + ISTEP -1
            ILA_ALL(XL_IBEG:XL_END) = DRIFT_PACK_GLOBAL(IBEGIN:IEND)
            JLA_ALL(XL_IBEG:XL_END) = DRIFT_PACK_GLOBAL(IEND+1:IEND + ISTEP)
            XLA_ALL(XL_IBEG:XL_END) = DRIFT_PACK_GLOBAL(IEND+ISTEP+1:IEND+ (ISTEP*2))
            YLA_ALL(XL_IBEG:XL_END) = DRIFT_PACK_GLOBAL(IEND+(ISTEP*2)+1:IEND+ (ISTEP*3))
            ZLA_ALL(XL_IBEG:XL_END) = DRIFT_PACK_GLOBAL(IEND+(ISTEP*3)+1:IEND+ (ISTEP*4))
        ENDDO

        !     CALL MAP_GLOBAL_LOCAL(0) ! (XLA, YLA, ZLA, XLA_ALL,YLA_ALL,ZLA_ALL)    !OUT:XLA,YLA,LLA,KLA,BELVLA,HPLA
        NPD = 0
        IF(ALLOCATED(XLA))THEN
            ! NUMBER OF DRIFTERS IN EACH PARTITION CAN CHANGE EACH TIMESTEP
            DEALLOCATE (XLA, YLA, ZLA, LLA, KLA , HPLA, BELVLA)
        END IF
        ALLOCATE (XLA(0), YLA(0), ZLA(0), LLA(0) )
        DO NP=1, sum(PROC_SIZE_ARR)
            ILA_LOC = XLOC( INT(ILA_ALL(NP)))
            JLA_LOC = YLOC(INT(JLA_ALL(NP)))
            L_TEMP = LIJ( ILA_LOC, JLA_LOC)
            IF (INSIDE_DOMAIN(L_TEMP)) THEN
                NPD = NPD + 1
                LLA = [LLA, L_TEMP]
                XLA = [XLA, XLA_ALL(NP)]
                YLA = [YLA, YLA_ALL(NP)]
                ZLA = [ZLA, ZLA_ALL(NP)]
            END IF
        END DO

        ALLOCATE(KLA(NPD),HPLA(NPD),BELVLA(NPD))
        KLA=0
        HPLA=0.
        BELVLA=0.


        DO NP=1,NPD
            IF (LLA(NP)>=2) CALL DRIFTERWDEP(LLA(NP),NP,BELVLA(NP),HPLA(NP))

            IF (LLA(NP)>=2) CALL DRIFTERLAYER(LLA(NP),NP,BELVLA(NP), &
                HPLA(NP),KLA(NP),ZLA(NP))
        END DO
#endif
    END SUBROUTINE


    FUNCTION GHOSTZONE(L) RESULT(INSIDE)   ! **********************************************
        LOGICAL(4)::INSIDE
        INTEGER(4),INTENT(IN)::L
        INTEGER(4):: ILOCATION, JLOCATION
        ILOCATION = IL(L)
        JLOCATION = JL(L)
        INSIDE=.FALSE.
        IF (ILOCATION <= 2 .OR. ILOCATION >= IC-2) THEN
            INSIDE=.TRUE.
        END IF
        IF (JLOCATION <= 2 .OR. JLOCATION >= JC-2) THEN
            INSIDE=.TRUE.
        END IF
    END FUNCTION

    FUNCTION INSIDE_DOMAIN(L) RESULT(INSIDE)   ! **********************************************
        LOGICAL(4)::INSIDE
        INTEGER(4),INTENT(IN)::L
        INTEGER(4):: ILOCATION, JLOCATION
        ILOCATION = IL(L)
        JLOCATION = JL(L)
        INSIDE=.FALSE.
        IF (ILOCATION > 2 .AND. ILOCATION < IC-1) THEN
            IF (JLOCATION >2 .AND. JLOCATION < JC-1) THEN
                INSIDE=.TRUE.  ! RETURN TRUE IF L WITHIN COMPUTATIONAL DOMAIN
            END IF
        END IF
    END FUNCTION

END MODULE
