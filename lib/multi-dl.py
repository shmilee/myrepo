#!/usr/bin/python
#coding=utf-8
import curses
import sys
from threading import Thread
import subprocess
import locale
import time
import os
from os.path import basename
import argparse
from urllib.parse import urlsplit
import signal
import sys
ui = None
def signal_handler(signal, frame):
    ui.quiet()
    while ui.is_alive():pass
    sys.exit(1)
signal.signal(signal.SIGINT, signal_handler)

locale.setlocale(locale.LC_ALL, "")
def url2name(url):
    return basename(urlsplit(url)[2])
class Down(Thread):
    def __init__(self, url, index, cmd):
        Thread.__init__(self)
        self.filename = url2name(url)
        self.finish = False
        self.index = index
        self.url = url
        self.total = 0
        self.downs = 0
        self.progress = 0
        self.cmd = cmd.replace("%u", url)
        self.nstart = True
        self.out(self.cmd)
        self.exit_code = 0
        self.p = None
    def out(self, strs):
        self.msg = strs
    def run(self):
        self.nstart = False
        self.p = subprocess.Popen(self.cmd, bufsize=0, stdin=subprocess.PIPE , stdout=subprocess.PIPE, stderr=subprocess.STDOUT, shell=True, universal_newlines=True)
        while self.p.poll() is None:
            line = self.p.stdout.readline()
            if line != None:
                self.out(line)
            time.sleep(0.2)
        if self.msg != "User Stop.": 
            self.exit_code = self.p.returncode
            if self.exit_code == None or self.exit_code == 0:
                self.exit_code = 0
                self.out("Done")
            else:
                self.out("Exit:%d" % self.exit_code)
class UI(Thread):
    def __init__(self, downs, ts, autoscroll, autoexit):
            Thread.__init__(self)
            self.downs = downs
            self.ts = ts
            self.autoscroll = autoscroll
            self.autoexit = autoexit
            self.done = 1
            self.msg = ""
            self.q = False
            self.sleep = 0
    def draw(self, y, x, strs, color=1):
        if(len(strs) + x > self.mx):strs = strs[ :(self.mx - (len(strs) + x))]
        if y + 1 > self.my:
            return
        self.window.addstr(y, x, strs, curses.color_pair(color))
    def onkey(self, key):
        if key == -1 :
            return
        self.sleep =  10000
        #self.msg = "Key:%d" % key
        if key == curses.KEY_LEFT:
            self.ts = self.ts -1
            if self.ts < 1: self.ts =1
        if key == curses.KEY_RIGHT:
            self.ts = self.ts  + 1
        if key == curses.KEY_PPAGE:
            self.autoscroll = False
            self.select = self.select - (self.my - 6) 
        if key == curses.KEY_NPAGE:
            self.autoscroll = False
            self.select = self.select + (self.my - 6)
        if key == curses.KEY_UP:
            self.autoscroll = False
            self.select = self.select - 1
        if key == curses.KEY_DOWN:
            self.autoscroll = False
            self.select = self.select + 1
        if key == ord('s'):
            self.autoscroll = not self.autoscroll 
        if key == ord('e'):
            self.autoexit = not self.autoexit 
        if key == ord('q'):
            if self.q:
                self.msg = "Kills"
                self.quiet()
                self.msg = "Kill Done."
            else:self.q = True
        else:self.q = False
    def run(self):
        try:
            self.window = curses.initscr()
            self.curses = curses
            self.curses.noecho()
            self.curses.cbreak()
            self.curses.curs_set(0)
            self.window.keypad(1)
            self.window.nodelay(1)
            self.select = 0
            curses.start_color()
            curses.use_default_colors()
            curses.init_pair(1, curses.COLOR_GREEN, -1)
            curses.init_pair(2, curses.COLOR_CYAN, -1)
            curses.init_pair(3, curses.COLOR_MAGENTA, -1)
            curses.init_pair(4, curses.COLOR_BLUE, -1)
            curses.init_pair(5, curses.COLOR_YELLOW, -1)
            curses.init_pair(6, curses.COLOR_RED, -1)
            self.window.bkgd(curses.color_pair(1))
            while True:
                ats = [] #活动的线程
                nts = [] #没有启动的线程
                ets = [] #已经结束的线程
                for d in self.downs:
                    if d.is_alive():ats.append(d)
                    elif d.nstart:nts.append(d)
                    else:ets.append(d)
                if self.autoscroll and len(ats) > 0:self.select = ats[0].index * 2 - 2
                asts = self.ts - len(ats)  #可启动的线程数
                if asts > len(nts):asts = len(nts)
                if asts > 0:
                    for i in range(asts):
                        nts[i].start()
                        while not nts[i].is_alive() : time.sleep(0.1)
                        ats.append(nts[i])
                    nts = nts[asts:]
                # Update UI
                self.sleep = self.sleep + 1
                self.onkey(self.window.getch())
                if self.sleep > 50: 
                    self.myx = self.window.getmaxyx()
                    self.mx = self.myx[1]
                    self.my = self.myx[0]
                    self.window.clear()
                    self.draw(1, 1, "Total:%-5d Succeed:%-5d Error:%-5d Running:%-5d Waiting:%-5d Threads:%5d" % (len(self.downs)  ,
                        len([d for d in ets if d.exit_code == 0 ]),
                        len([d for d in ets if d.exit_code != 0 ]),
                        len(ats),
                        len(nts),
                        self.ts))
                    downs_len = len(self.downs)
                    select = self.select
                    if select < 0 :select = 0
                    elif downs_len*2 - (self.my - 6) < 0 : self.select = 0
                    elif select > downs_len * 2 - (self.my - 6): select = downs_len * 2 - (self.my - 6)
                    self.select = select
                    y = 3 - select
                    for i in range(0, downs_len):
                        d = self.downs[i]
                        if y >= 3 and y < self.my - 3:
                            if d in ats:self.draw(y, 1, "%4d.R" % d.index, 2)
                            elif d in nts:self.draw(y, 1, "%4d.W" % d.index, 3)
                            elif d.exit_code != 0:self.draw(y, 1, "%4d.E" % d.index, 4)
                            else:self.draw(y, 1, "%4d.S" % d.index, 5)
                            self.draw(y, 7, (" %s" % (d.filename)), 6)
                        if  y + 1 >= 3 and  y + 1 < self.my - 3:
                            if d in ats:self.draw(y + 1, 7, "-->" + d.msg)
                            else:self.draw(y + 1, 6, d.msg)
                        y = y + 2
                    self.window.border(0)
                    self.window.hline(2, 1, '-', self.mx - 2)
                    self.window.hline(self.my - 3, 1, '-', self.mx - 2)
                    if self.autoscroll:
                        self.draw(self.my - 2, self.mx - 1 - 10, "AUTOSCROLL")
                    if self.autoexit:
                        self.draw(self.my - 2, self.mx - 1 - 20, "AUTOEXIT")
                    help = "[qq=quit,s=auto_scroll,e=auto_exit,UP|DOWN=scroll,LEFT|RIGHT=+/-Threads]"
                    self.draw(self.my - 2, 1, help)
                    self.draw(self.my - 2, len(help) + 2, self.msg)
                    self.window.refresh()
                    self.sleep = 0
                if len(ats) == 0 and len(nts) == 0:
                    self.done = 0
                    if self.autoexit:
                        break
                time.sleep(0.01)
        except Exception as e:
            self.window.clear()
            self.draw(10, 10, "UI Thread exception:%s" % e, 1)
            self.window.refresh()
            time.sleep(3)
        finally:
            self.close()
    def quiet(self):
       for d in self.downs:
           d.nstart = False
       for d in self.downs:
           d.out("User Stop.")
           if d.p != None :
               try:
                   d.p.terminate()
               except:pass
           d.exit_code = 1
           d.out("User Stop.")
       self.autoexit = True
    def close(self):
            try:
                self.window.clear()
                self.window.refresh()
                self.curses.echo()
                self.curses.nocbreak()
                self.window.keypad(0)
                self.curses.endwin()
            except Exception as e:
                print("UI Close error:%s" % e)
def main(args):
        global ui
        downs = []
        downIndex = 0
        for u in args.urls:
            downIndex = downIndex + 1
            d = Down(u, downIndex, args.cmd)
            downs.append(d);
        ui = UI(downs, args.threads, args.autoscroll, args.autoexit)
        ui.start()
        ui.join()
        sys.exit(ui.done)
if (__name__ == "__main__"):
    parser = argparse.ArgumentParser(description="同时下载多个URL v1.0 by yukunyi@yeah.net")
    parser.add_argument('-c',"--command", dest='cmd', help='下载的命令(%%u为url,默认wget -c -t 3 %%u)', default="wget -c -t 3 %u")
    parser.add_argument('-t',"--thread-size", dest='threads', help='同时下载数', default=8, type=int)
    parser.add_argument('-u',"--urls", dest='urls', help='要下载的urls', nargs='+', required=True)
    parser.add_argument('-e',"--autoexit", dest='autoexit',action="store_true", help='结束后不需要确认,自动退出', default=False)
    parser.add_argument('-s',"--autoscroll", dest='autoscroll',action="store_true", help='自动滚动到最新活动', default=True)
    args = parser.parse_args()
    main(args)
