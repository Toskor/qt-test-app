#include "mainwindow.h"
#include "./ui_mainwindow.h"
#include <QApplication>
#include <QPushButton>

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent)
    , ui(new Ui::MainWindow)
{
    ui->setupUi(this);
    
    // Set fixed window size
    setFixedSize(400, 300);
    
    // Connect exit button to close application
    connect(ui->exitButton, &QPushButton::clicked, this, &QApplication::quit);
}

MainWindow::~MainWindow()
{
    delete ui;
}
