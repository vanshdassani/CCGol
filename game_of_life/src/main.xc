// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 16                 //image height
#define  IMWD 16                  //image width
#define  num_workers 4

typedef unsigned char uchar;      //using uchar as shorthand

on tile[0] : port p_scl = XS1_PORT_1E;         //interface ports to orientation
on tile[0] : port p_sda = XS1_PORT_1F;

on tile[0] : in port buttons = XS1_PORT_4E; //port for buttons
on tile[1] : out port leds = XS1_PORT_4F; //port for leds

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6


int xadd (int i, int a) {
    i += a;
    while (i < 0) i += IMWD;
    while (i >= IMWD) i -= IMWD;
    return i;
}

int yadd (int i, int a) {
    i += a;
    while (i < 0) i += IMHT;
    while (i >= IMHT) i -= IMHT;
    return i;
}

void Worker(uchar id, chanend worker_distributor) {
    //printf("Worker %d started\n", id);
    uchar board_segment[(IMWD/2)+ 2 ][(IMHT/(num_workers/2))+ 2 ];
    uchar next_board_segment[(IMWD/2)][(IMHT/(num_workers/2))];
    uchar a;
    uchar count = 0;
//    uchar send_permission = 1;
    uchar processing = 1;

    while (processing){
    for(int i = 0; i < (IMHT/(num_workers/2)+2); i++) {
        for(int j = 0; j < ((IMWD/2)+2); j++) {
            worker_distributor :> board_segment[j][i];
        }
    }
    //printf("Worker %d data in complete \n", id);


    //PROCESSING

    for(int y = 1; y < (IMHT/(num_workers/2)+1); y ++) {
        for(int x = 1; x < ((IMWD/2)+1); x ++) { //for all the cells in the board
            //calculate the adjacent cells
            count = 0;
            for (int k=-1; k<=1; k++) {
                        for (int l=-1; l<=1; l++) {
                            if (k || l) {
                                if (board_segment[ (x + l) ][ (y + k) ] == 255) {
                                    count++;
                                }
                            }
                        }
            }

            a = count;

            //calculate whether the cell should die
            if(board_segment[x][y] == 255) {
                    if( a < 2 || a > 3) {
                        next_board_segment[x-1][y-1] = 0;
                    }
                    else {
                        next_board_segment[x-1][y-1] = 255;
                    }
            }
            else {
                if(a == 3) {
                    next_board_segment[x-1][y-1] = 255;
                }
                else {
                    next_board_segment[x-1][y-1] = 0;
                }
            }

        }
    }
    //printf("Worker %d processing complete \n", id);

    worker_distributor <: (uchar)id;

//    if(send_permission == 1) {
        for(int y = 0; y < (IMHT/(num_workers/2)); y++) {
                for(int x = 0; x < (IMWD/2); x++) {
                    worker_distributor <: next_board_segment[x][y];
                }
        }
//    }
    //printf("\nWorker %d finished\n", id);
        worker_distributor :> processing;
    }
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend c_out)
{
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }

  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x++ ) {
      c_out <: line[ x ];
      //printf( "-%4.1d ", line[ x ] ); //show image values
    }
    //printf( "\n" );
  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_in, chanend c_out, chanend fromAcc, chanend fromButtons, chanend distributor_worker[4])
{
//  uchar val;
  uchar processing_rounds;
  uchar max_rounds;
  uchar current_board[IMWD][IMHT];
  uchar new_board[IMWD][IMHT];
  uchar workers_finished;
  uchar data_in_complete = 0;
  uchar button_input;
//  uchar please_output;

  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
//  printf( "Waiting for Board Tilt...\n" );
//  fromAcc :> int value;

  printf("Waiting for Button Press...\n");
  fromButtons :> button_input;

  if (button_input == 14) {
      //INITIALISATION
      for( int y = 0; y < IMHT; y++ ) {   //go through all lines
          for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
              c_in :> current_board[x][y]; //read in and store pixel value
          }
      }
      data_in_complete = 1;
  }

  printf( "Processing...\n" );

  processing_rounds = 0;
  max_rounds = 100;

  while((processing_rounds < max_rounds) && data_in_complete) {
      //if(data out request == 1) { do a print} else jsut run the code
//      c_out :> please_output;
//      printf("processing round %d begun..\n", processing_rounds+1);
        workers_finished = 0;
        int offset_x = 0;
        int offset_y = 0;

       par for(int i = 0; i < num_workers; i++) {
            if(i == 0) {
                offset_x = 0;
                offset_y = 0;
            }
            else if(i == 1) {
                offset_x = (IMWD/2);
                offset_y = 0;
            }
            else if(i == 2) {
                offset_x = 0;
                offset_y = (IMHT/(num_workers/2));
            }
            else if(i == 3) {
                offset_x = (IMWD/2);
                offset_y = (IMHT/(num_workers/2));
            }

              for(int j = -1; j < ((IMHT/(num_workers/2))+1); j ++) {
                  for(int k = -1; k < ((IMWD/2)+1); k++) {
                      distributor_worker[i] <: current_board[xadd( offset_x, k )][yadd( offset_y, j )];
                  }
              }
        }

        while(workers_finished<num_workers) {
            select {
               case distributor_worker[uchar j] :> uchar data:
               //printf("channel %d gets %d data\n", j, data);

               if(j == 0) {
                   offset_x = 0;
                   offset_y = 0;
               }
               else if(j == 1) {
                   offset_x = (IMWD/2);
                   offset_y = 0;
               }
               else if(j == 2) {
                   offset_x = 0;
                   offset_y = (IMHT/(num_workers/2));
               }
               else if(j == 3) {
                   offset_x = (IMWD/2);
                   offset_y = (IMHT/(num_workers/2));
               }

               for(int l = 0; l < (IMHT/(num_workers/2)); l ++) {
                   for(int k = 0; k < (IMWD/2); k++) {
                       distributor_worker[j] :> new_board[offset_x + k][offset_y + l];
                   }
               }

               workers_finished++;

               break;
           }
        }

        for(int j = 0; j < (IMHT); j ++) {
              for(int k = 0; k < (IMWD); k++) {
                  current_board[k][j] = new_board[k][j];
              }
        }

        printf( "%d processing round completed...\n", (processing_rounds+1));
        processing_rounds++;
        if (processing_rounds < max_rounds) {
            for (uchar z = 0; z < num_workers; z++) {
                distributor_worker[z] <: (uchar) 1;
            }
        }

//        if (please_output) {
//            //Prints out the board
//              for( int j = 0; j < IMHT; j++ ) {
//                 // printf("\n");
//                      for( int i = 0; i < IMWD; i++ ) {
//                             //printf( "-%4.1d ", current_board[i][j]);
//                             c_out <: (uchar)current_board[i][j];
//                         }
//              }
//              please_output = 0;
//        }
  }
  //Prints out the board
  for( int j = 0; j < IMHT; j++ ) {
     // printf("\n");
          for( int i = 0; i < IMWD; i++ ) {
                 //printf( "-%4.1d ", current_board[i][j]);
                 c_out <: (uchar)current_board[i][j];
             }
  }


}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in, chanend from_buttons)
{
  uchar button_in;
  from_buttons :> button_in;
      if (button_in == 13) {
//      c_in <: 1;
      int res;
      uchar line[ IMWD ];

      //Open PGM file
      printf( "DataOutStream: Start...\n" );
      res = _openoutpgm( outfname, IMWD, IMHT );
      if( res ) {
        printf( "DataOutStream: Error opening %s\n.", outfname );
        return;
      }

      //Compile each line of the image and write the image line-by-line
      for( int y = 0; y < IMHT; y++ ) {
        for( int x = 0; x < IMWD; x++ ) {
          c_in :> line[ x ];
        }
        _writeoutline( line, IMWD );
        //printf( "DataOutStream: Line written...\n" );
      }
      //Close the PGM image
      _closeoutpgm();
      printf( "DataOutStream: Done...\n" );
      return;
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void orientation( client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;
  int tilted = 0;

  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }
  
  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  //Probe the orientation x-axis forever
  while (1) {

    //check until new orientation data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor after first tilt
    if (!tilted) {
      if (x>30) {
        tilted = 1 - tilted;
        toDist <: 1;
      }
    }
  }
}

void button_listener(in port b, chanend to_dist, chanend to_dataout) {
    uchar input;
    while (1) {
        b when pinseq(15) :> input; //no buttons pressed
        b when pinsneq(15) :> input; //some button pressed
        if (input == 14) {
            to_dist <: input;
//            to_dataout <: input;
        } else if (input == 13) {
            to_dataout <: input;
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {

i2c_master_if i2c[1];               //interface to orientation

chan c_inIO, c_outIO, c_control, distributor_worker[4], buttons_to_dist, buttons_to_dataout;    //extend your channel definitions here

par {
    on tile[0] : i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    on tile[0] : orientation(i2c[0],c_control);        //client thread reading orientation data
    on tile[0] : DataInStream("test.pgm", c_inIO);          //thread to read in a PGM image
    on tile[1] : DataOutStream("testout16.pgm", c_outIO, buttons_to_dataout);       //thread to write out a PGM image
    on tile[0] : distributor(c_inIO, c_outIO, c_control, buttons_to_dist, distributor_worker);//thread to coordinate work on image
    on tile[1] : Worker((uchar)1, distributor_worker[0]);
    on tile[1] : Worker((uchar)2, distributor_worker[1]);
    on tile[1] : Worker((uchar)3, distributor_worker[2]);
    on tile[1] : Worker((uchar)4, distributor_worker[3]);
    on tile[0] : button_listener(buttons, buttons_to_dist, buttons_to_dataout);
  }

  return 0;
}
