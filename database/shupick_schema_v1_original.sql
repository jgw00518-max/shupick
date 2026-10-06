-- MySQL dump 10.13  Distrib 8.0.46, for Win64 (x86_64)
--
-- Host: 192.168.20.76    Database: shupick
-- ------------------------------------------------------
-- Server version	8.0.46

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `adds_to_cart`
--

DROP TABLE IF EXISTS `adds_to_cart`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `adds_to_cart` (
  `customer_customer_id` varchar(45) NOT NULL,
  `product_product_code` varchar(45) NOT NULL,
  `cart_id` int DEFAULT NULL,
  `product_name` varchar(45) DEFAULT NULL,
  `quantity` int DEFAULT NULL,
  `added_at` datetime DEFAULT NULL,
  PRIMARY KEY (`customer_customer_id`,`product_product_code`),
  KEY `fk_customer_has_product2_product1_idx` (`product_product_code`),
  KEY `fk_customer_has_product2_customer1_idx` (`customer_customer_id`),
  CONSTRAINT `fk_customer_has_product2_customer1` FOREIGN KEY (`customer_customer_id`) REFERENCES `customer` (`customer_id`),
  CONSTRAINT `fk_customer_has_product2_product1` FOREIGN KEY (`product_product_code`) REFERENCES `product` (`product_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `approves`
--

DROP TABLE IF EXISTS `approves`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `approves` (
  `employee_employee_id` varchar(45) NOT NULL,
  `purchaserequistion_purchaserequistion_id` int NOT NULL,
  `sumbitted_at` datetime DEFAULT NULL,
  `processing_status` varchar(45) DEFAULT NULL,
  `approved_at` datetime DEFAULT NULL,
  PRIMARY KEY (`employee_employee_id`,`purchaserequistion_purchaserequistion_id`),
  KEY `fk_employee_has_purchaserequistion_purchaserequistion1_idx` (`purchaserequistion_purchaserequistion_id`),
  KEY `fk_employee_has_purchaserequistion_employee1_idx` (`employee_employee_id`),
  CONSTRAINT `fk_employee_has_purchaserequistion_employee1` FOREIGN KEY (`employee_employee_id`) REFERENCES `employee` (`employee_id`),
  CONSTRAINT `fk_employee_has_purchaserequistion_purchaserequistion1` FOREIGN KEY (`purchaserequistion_purchaserequistion_id`) REFERENCES `purchaserequistion` (`purchaserequistion_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `belongs_to`
--

DROP TABLE IF EXISTS `belongs_to`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `belongs_to` (
  `branch_branch_id` int NOT NULL,
  `employee_employee_id` varchar(45) NOT NULL,
  `belong_start_at` datetime DEFAULT NULL,
  `belong_end_at` datetime DEFAULT NULL,
  PRIMARY KEY (`branch_branch_id`,`employee_employee_id`),
  KEY `fk_branch_has_employee_employee1_idx` (`employee_employee_id`),
  KEY `fk_branch_has_employee_branch1_idx` (`branch_branch_id`),
  CONSTRAINT `fk_branch_has_employee_branch1` FOREIGN KEY (`branch_branch_id`) REFERENCES `branch` (`branch_id`),
  CONSTRAINT `fk_branch_has_employee_employee1` FOREIGN KEY (`employee_employee_id`) REFERENCES `employee` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `branch`
--

DROP TABLE IF EXISTS `branch`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `branch` (
  `branch_id` int NOT NULL,
  `branch_name` varchar(45) DEFAULT NULL,
  `branch_address` varchar(45) DEFAULT NULL,
  `branch_phone` varchar(45) DEFAULT NULL,
  `latitude` double DEFAULT NULL,
  `longitude` double DEFAULT NULL,
  PRIMARY KEY (`branch_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `customer`
--

DROP TABLE IF EXISTS `customer`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `customer` (
  `customer_id` varchar(45) NOT NULL,
  `password` varchar(45) DEFAULT NULL,
  `name` varchar(45) DEFAULT NULL,
  `phone` varchar(45) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `email` varchar(45) DEFAULT NULL,
  `reward_points` int DEFAULT NULL,
  `branch_has_employee1_branch_branch_id` int NOT NULL,
  `branch_has_employee1_employee_employee_id` varchar(45) NOT NULL,
  PRIMARY KEY (`customer_id`,`branch_has_employee1_branch_branch_id`,`branch_has_employee1_employee_employee_id`),
  KEY `fk_customer_branch_has_employee11_idx` (`branch_has_employee1_branch_branch_id`,`branch_has_employee1_employee_employee_id`),
  CONSTRAINT `fk_customer_branch_has_employee11` FOREIGN KEY (`branch_has_employee1_branch_branch_id`, `branch_has_employee1_employee_employee_id`) REFERENCES `delivery` (`branch_branch_id`, `employee_employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `delivery`
--

DROP TABLE IF EXISTS `delivery`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `delivery` (
  `branch_branch_id` int NOT NULL,
  `employee_employee_id` varchar(45) NOT NULL,
  `delivery_id` int DEFAULT NULL,
  `delivery_at` datetime DEFAULT NULL,
  `arrived_at` datetime DEFAULT NULL,
  `delivery_quantity` int DEFAULT NULL,
  `product_info` varchar(100) DEFAULT NULL,
  `delivery_status` varchar(45) DEFAULT NULL,
  PRIMARY KEY (`branch_branch_id`,`employee_employee_id`),
  KEY `fk_branch_has_employee1_employee1_idx` (`employee_employee_id`),
  KEY `fk_branch_has_employee1_branch1_idx` (`branch_branch_id`),
  CONSTRAINT `fk_branch_has_employee1_branch1` FOREIGN KEY (`branch_branch_id`) REFERENCES `branch` (`branch_id`),
  CONSTRAINT `fk_branch_has_employee1_employee1` FOREIGN KEY (`employee_employee_id`) REFERENCES `employee` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `employee`
--

DROP TABLE IF EXISTS `employee`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `employee` (
  `employee_id` varchar(45) NOT NULL,
  `employee_password` varchar(45) DEFAULT NULL,
  `department` int DEFAULT NULL,
  `position` varchar(45) DEFAULT NULL,
  `employee_name` varchar(45) DEFAULT NULL,
  PRIMARY KEY (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `favorites`
--

DROP TABLE IF EXISTS `favorites`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `favorites` (
  `customer_customer_id` varchar(45) NOT NULL,
  `product_product_code` varchar(45) NOT NULL,
  `favorite_id` int DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  PRIMARY KEY (`customer_customer_id`,`product_product_code`),
  KEY `fk_customer_has_product1_product1_idx` (`product_product_code`),
  KEY `fk_customer_has_product1_customer1_idx` (`customer_customer_id`),
  CONSTRAINT `fk_customer_has_product1_customer1` FOREIGN KEY (`customer_customer_id`) REFERENCES `customer` (`customer_id`),
  CONSTRAINT `fk_customer_has_product1_product1` FOREIGN KEY (`product_product_code`) REFERENCES `product` (`product_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `inquiry_response`
--

DROP TABLE IF EXISTS `inquiry_response`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `inquiry_response` (
  `customer_customer_id` varchar(45) NOT NULL,
  `employee_employee_id` varchar(45) NOT NULL,
  `inquiry_at` datetime DEFAULT NULL,
  `inquiry_title` varchar(45) DEFAULT NULL,
  `response_at` datetime DEFAULT NULL,
  `inquiry_content` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`customer_customer_id`,`employee_employee_id`),
  KEY `fk_customer_has_employee2_employee1_idx` (`employee_employee_id`),
  KEY `fk_customer_has_employee2_customer1_idx` (`customer_customer_id`),
  CONSTRAINT `fk_customer_has_employee2_customer1` FOREIGN KEY (`customer_customer_id`) REFERENCES `customer` (`customer_id`),
  CONSTRAINT `fk_customer_has_employee2_employee1` FOREIGN KEY (`employee_employee_id`) REFERENCES `employee` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `manufacturer`
--

DROP TABLE IF EXISTS `manufacturer`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `manufacturer` (
  `manufacturer_id` int NOT NULL,
  `manufacturer_name` varchar(45) DEFAULT NULL,
  PRIMARY KEY (`manufacturer_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `order`
--

DROP TABLE IF EXISTS `order`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `order` (
  `customer_customer_id` varchar(45) NOT NULL,
  `product_product_code` varchar(45) NOT NULL,
  `employee_employee_id` varchar(45) NOT NULL,
  `branch_branch_id` int NOT NULL,
  `review_review_id` int NOT NULL,
  `purchase_confirmed_at` datetime DEFAULT NULL,
  `order_id` int DEFAULT NULL,
  `payment_id` int DEFAULT NULL,
  `order_quantity` int DEFAULT NULL,
  `ordered_at` datetime DEFAULT NULL,
  PRIMARY KEY (`customer_customer_id`,`product_product_code`,`employee_employee_id`,`branch_branch_id`,`review_review_id`),
  KEY `fk_customer_has_product3_product1_idx` (`product_product_code`),
  KEY `fk_customer_has_product3_customer1_idx` (`customer_customer_id`),
  KEY `fk_customer_has_product3_employee1_idx` (`employee_employee_id`),
  KEY `fk_customer_has_product3_branch1_idx` (`branch_branch_id`),
  KEY `fk_customer_has_product3_review1_idx` (`review_review_id`),
  CONSTRAINT `fk_customer_has_product3_branch1` FOREIGN KEY (`branch_branch_id`) REFERENCES `branch` (`branch_id`),
  CONSTRAINT `fk_customer_has_product3_customer1` FOREIGN KEY (`customer_customer_id`) REFERENCES `customer` (`customer_id`),
  CONSTRAINT `fk_customer_has_product3_employee1` FOREIGN KEY (`employee_employee_id`) REFERENCES `employee` (`employee_id`),
  CONSTRAINT `fk_customer_has_product3_product1` FOREIGN KEY (`product_product_code`) REFERENCES `product` (`product_code`),
  CONSTRAINT `fk_customer_has_product3_review1` FOREIGN KEY (`review_review_id`) REFERENCES `review` (`review_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `owns`
--

DROP TABLE IF EXISTS `owns`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `owns` (
  `customer_customer_id` varchar(45) NOT NULL,
  `review_review_id` int NOT NULL,
  `usage_at` datetime DEFAULT NULL,
  `earned_at` datetime DEFAULT NULL,
  PRIMARY KEY (`customer_customer_id`,`review_review_id`),
  KEY `fk_customer_has_review1_review1_idx` (`review_review_id`),
  KEY `fk_customer_has_review1_customer1_idx` (`customer_customer_id`),
  CONSTRAINT `fk_customer_has_review1_customer1` FOREIGN KEY (`customer_customer_id`) REFERENCES `customer` (`customer_id`),
  CONSTRAINT `fk_customer_has_review1_review1` FOREIGN KEY (`review_review_id`) REFERENCES `review` (`review_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `payment`
--

DROP TABLE IF EXISTS `payment`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `payment` (
  `customer_customer_id` varchar(45) NOT NULL,
  `employee_employee_id` varchar(45) NOT NULL,
  `payment_id` int DEFAULT NULL,
  `payment_method` varchar(45) DEFAULT NULL,
  `payment_amount` int DEFAULT NULL,
  `paid_at` datetime DEFAULT NULL,
  PRIMARY KEY (`customer_customer_id`,`employee_employee_id`),
  KEY `fk_customer_has_employee1_employee1_idx` (`employee_employee_id`),
  KEY `fk_customer_has_employee1_customer1_idx` (`customer_customer_id`),
  CONSTRAINT `fk_customer_has_employee1_customer1` FOREIGN KEY (`customer_customer_id`) REFERENCES `customer` (`customer_id`),
  CONSTRAINT `fk_customer_has_employee1_employee1` FOREIGN KEY (`employee_employee_id`) REFERENCES `employee` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `picks_up`
--

DROP TABLE IF EXISTS `picks_up`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `picks_up` (
  `customer_customer_id` varchar(45) NOT NULL,
  `branch_branch_id` int NOT NULL,
  `employee_employee_id` varchar(45) NOT NULL,
  `picks_up_date` datetime DEFAULT NULL,
  PRIMARY KEY (`customer_customer_id`,`branch_branch_id`,`employee_employee_id`),
  KEY `fk_customer_has_branch_branch1_idx` (`branch_branch_id`),
  KEY `fk_customer_has_branch_customer1_idx` (`customer_customer_id`),
  KEY `fk_customer_has_branch_employee1_idx` (`employee_employee_id`),
  CONSTRAINT `fk_customer_has_branch_branch1` FOREIGN KEY (`branch_branch_id`) REFERENCES `branch` (`branch_id`),
  CONSTRAINT `fk_customer_has_branch_customer1` FOREIGN KEY (`customer_customer_id`) REFERENCES `customer` (`customer_id`),
  CONSTRAINT `fk_customer_has_branch_employee1` FOREIGN KEY (`employee_employee_id`) REFERENCES `employee` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `places_a_purchases_order`
--

DROP TABLE IF EXISTS `places_a_purchases_order`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `places_a_purchases_order` (
  `product_product_code` varchar(45) NOT NULL,
  `manufacturer_manufacturer_id` int NOT NULL,
  `employee_employee_id` varchar(45) NOT NULL,
  `purchaserequistion_purchaserequistion_id` int NOT NULL,
  `order_item` varchar(45) DEFAULT NULL,
  `order_at` datetime DEFAULT NULL,
  PRIMARY KEY (`product_product_code`,`manufacturer_manufacturer_id`,`employee_employee_id`,`purchaserequistion_purchaserequistion_id`),
  KEY `fk_product_has_manufacturer1_manufacturer1_idx` (`manufacturer_manufacturer_id`),
  KEY `fk_product_has_manufacturer1_product1_idx` (`product_product_code`),
  KEY `fk_product_has_manufacturer1_employee1_idx` (`employee_employee_id`),
  KEY `fk_product_has_manufacturer1_purchaserequistion1_idx` (`purchaserequistion_purchaserequistion_id`),
  CONSTRAINT `fk_product_has_manufacturer1_employee1` FOREIGN KEY (`employee_employee_id`) REFERENCES `employee` (`employee_id`),
  CONSTRAINT `fk_product_has_manufacturer1_manufacturer1` FOREIGN KEY (`manufacturer_manufacturer_id`) REFERENCES `manufacturer` (`manufacturer_id`),
  CONSTRAINT `fk_product_has_manufacturer1_product1` FOREIGN KEY (`product_product_code`) REFERENCES `product` (`product_code`),
  CONSTRAINT `fk_product_has_manufacturer1_purchaserequistion1` FOREIGN KEY (`purchaserequistion_purchaserequistion_id`) REFERENCES `purchaserequistion` (`purchaserequistion_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `product`
--

DROP TABLE IF EXISTS `product`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `product` (
  `product_code` varchar(45) NOT NULL,
  `product_image` longblob,
  `product_name` varchar(45) DEFAULT NULL,
  `product_color` varchar(45) DEFAULT NULL,
  `product_price` int DEFAULT NULL,
  `stock_quantity` int DEFAULT NULL,
  PRIMARY KEY (`product_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `purchaserequistion`
--

DROP TABLE IF EXISTS `purchaserequistion`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `purchaserequistion` (
  `purchaserequistion_id` int NOT NULL,
  `title` varchar(45) DEFAULT NULL,
  `reson` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`purchaserequistion_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `receive_an_order`
--

DROP TABLE IF EXISTS `receive_an_order`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `receive_an_order` (
  `product_product_code` varchar(45) NOT NULL,
  `manufacturer_manufacturer_id` int NOT NULL,
  `employee_employee_id` varchar(45) NOT NULL,
  `receive_item` varchar(45) DEFAULT NULL,
  `receive_at` datetime DEFAULT NULL,
  PRIMARY KEY (`product_product_code`,`manufacturer_manufacturer_id`,`employee_employee_id`),
  KEY `fk_product_has_manufacturer_manufacturer1_idx` (`manufacturer_manufacturer_id`),
  KEY `fk_product_has_manufacturer_product1_idx` (`product_product_code`),
  KEY `fk_product_has_manufacturer_employee1_idx` (`employee_employee_id`),
  CONSTRAINT `fk_product_has_manufacturer_employee1` FOREIGN KEY (`employee_employee_id`) REFERENCES `employee` (`employee_id`),
  CONSTRAINT `fk_product_has_manufacturer_manufacturer1` FOREIGN KEY (`manufacturer_manufacturer_id`) REFERENCES `manufacturer` (`manufacturer_id`),
  CONSTRAINT `fk_product_has_manufacturer_product1` FOREIGN KEY (`product_product_code`) REFERENCES `product` (`product_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `resisters`
--

DROP TABLE IF EXISTS `resisters`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `resisters` (
  `product_product_code` varchar(45) NOT NULL,
  `employee_employee_id` varchar(45) NOT NULL,
  `register_at` datetime DEFAULT NULL,
  PRIMARY KEY (`product_product_code`,`employee_employee_id`),
  KEY `fk_product_has_employee_employee1_idx` (`employee_employee_id`),
  KEY `fk_product_has_employee_product1_idx` (`product_product_code`),
  CONSTRAINT `fk_product_has_employee_employee1` FOREIGN KEY (`employee_employee_id`) REFERENCES `employee` (`employee_id`),
  CONSTRAINT `fk_product_has_employee_product1` FOREIGN KEY (`product_product_code`) REFERENCES `product` (`product_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `return`
--

DROP TABLE IF EXISTS `return`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `return` (
  `branch_branch_id` int NOT NULL,
  `employee_employee_id` varchar(45) NOT NULL,
  `return_id` int DEFAULT NULL,
  `return_at` datetime DEFAULT NULL,
  `return_quantity` int DEFAULT NULL,
  `return_reason` varchar(100) DEFAULT NULL,
  `return_to_headquarter_at` datetime DEFAULT NULL,
  PRIMARY KEY (`branch_branch_id`,`employee_employee_id`),
  KEY `fk_branch_has_employee2_employee1_idx` (`employee_employee_id`),
  KEY `fk_branch_has_employee2_branch1_idx` (`branch_branch_id`),
  CONSTRAINT `fk_branch_has_employee2_branch1` FOREIGN KEY (`branch_branch_id`) REFERENCES `branch` (`branch_id`),
  CONSTRAINT `fk_branch_has_employee2_employee1` FOREIGN KEY (`employee_employee_id`) REFERENCES `employee` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `returns_product`
--

DROP TABLE IF EXISTS `returns_product`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `returns_product` (
  `customer_customer_id` varchar(45) NOT NULL,
  `employee_employee_id` varchar(45) NOT NULL,
  `branch_branch_id` int NOT NULL,
  `return_id` int DEFAULT NULL,
  `payment_id` int DEFAULT NULL,
  `return_quantity` int DEFAULT NULL,
  `refund_amount` int DEFAULT NULL,
  `requested_at` datetime DEFAULT NULL,
  `return_reason` varchar(100) DEFAULT NULL,
  `inspection_result` tinyint DEFAULT NULL,
  `rejection_reason` varchar(100) DEFAULT NULL,
  `refunded_at` datetime DEFAULT NULL,
  PRIMARY KEY (`customer_customer_id`,`employee_employee_id`,`branch_branch_id`),
  KEY `fk_customer_has_employee_employee1_idx` (`employee_employee_id`),
  KEY `fk_customer_has_employee_customer1_idx` (`customer_customer_id`),
  KEY `fk_customer_has_employee_branch1_idx` (`branch_branch_id`),
  CONSTRAINT `fk_customer_has_employee_branch1` FOREIGN KEY (`branch_branch_id`) REFERENCES `branch` (`branch_id`),
  CONSTRAINT `fk_customer_has_employee_customer1` FOREIGN KEY (`customer_customer_id`) REFERENCES `customer` (`customer_id`),
  CONSTRAINT `fk_customer_has_employee_employee1` FOREIGN KEY (`employee_employee_id`) REFERENCES `employee` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `review`
--

DROP TABLE IF EXISTS `review`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `review` (
  `review_id` int NOT NULL,
  `review_content` varchar(100) DEFAULT NULL,
  `rating` int DEFAULT NULL,
  `review_image` longblob,
  PRIMARY KEY (`review_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `stocks`
--

DROP TABLE IF EXISTS `stocks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `stocks` (
  `product_product_code` varchar(45) NOT NULL,
  `branch_branch_id` int NOT NULL,
  `stock_quantity` int DEFAULT NULL,
  `inventory_status` varchar(45) DEFAULT NULL,
  PRIMARY KEY (`product_product_code`,`branch_branch_id`),
  KEY `fk_product_has_branch_branch1_idx` (`branch_branch_id`),
  KEY `fk_product_has_branch_product1_idx` (`product_product_code`),
  CONSTRAINT `fk_product_has_branch_branch1` FOREIGN KEY (`branch_branch_id`) REFERENCES `branch` (`branch_id`),
  CONSTRAINT `fk_product_has_branch_product1` FOREIGN KEY (`product_product_code`) REFERENCES `product` (`product_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `views`
--

DROP TABLE IF EXISTS `views`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `views` (
  `customer_customer_id` varchar(45) NOT NULL,
  `product_product_code` varchar(45) NOT NULL,
  `view_id` int NOT NULL AUTO_INCREMENT,
  `viewed_at` datetime DEFAULT NULL,
  PRIMARY KEY (`view_id`,`customer_customer_id`,`product_product_code`),
  KEY `fk_customer_has_product_product1_idx` (`product_product_code`),
  KEY `fk_customer_has_product_customer_idx` (`customer_customer_id`),
  CONSTRAINT `fk_customer_has_product_customer` FOREIGN KEY (`customer_customer_id`) REFERENCES `customer` (`customer_id`),
  CONSTRAINT `fk_customer_has_product_product1` FOREIGN KEY (`product_product_code`) REFERENCES `product` (`product_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `write`
--

DROP TABLE IF EXISTS `write`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `write` (
  `customer_customer_id` varchar(45) NOT NULL,
  `review_review_id` int NOT NULL,
  `update_at` datetime DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  PRIMARY KEY (`customer_customer_id`,`review_review_id`),
  KEY `fk_customer_has_review_review1_idx` (`review_review_id`),
  KEY `fk_customer_has_review_customer1_idx` (`customer_customer_id`),
  CONSTRAINT `fk_customer_has_review_customer1` FOREIGN KEY (`customer_customer_id`) REFERENCES `customer` (`customer_id`),
  CONSTRAINT `fk_customer_has_review_review1` FOREIGN KEY (`review_review_id`) REFERENCES `review` (`review_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-10-02 15:40:12
