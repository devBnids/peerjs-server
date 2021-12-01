import { Server } from "socket.io";

let io: any;

export const socketConnection = (server: any) => {
  io = new Server(server);

  io.on('connection', (socket: any) => {
    console.log("Socket Connected!")
    socket.on('ping', () => {
      socket.emit('pong', { response: "Connection acknowledged" });
    });
  });
};